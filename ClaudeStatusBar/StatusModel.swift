import Foundation
import AppKit

enum ClaudeStatus: String, Codable {
    case idle
    case running
    case permissionRequired = "permission_required"
    case completed
    case error

    var emoji: String {
        switch self {
        case .idle: return "\u{1F634}"               // 😴
        case .running: return "\u{1F504}"            // 🔄
        case .permissionRequired: return "\u{26A0}\u{FE0F}" // ⚠️
        case .completed: return "\u{2705}"           // ✅
        case .error: return "\u{274C}"               // ❌
        }
    }

    /// Body color for the pixel art icon
    var bodyColor: NSColor {
        switch self {
        case .idle:               return NSColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1.0)
        case .running:            return NSColor(red: 0.77, green: 0.44, blue: 0.35, alpha: 1.0)
        case .permissionRequired: return NSColor(red: 1.00, green: 0.70, blue: 0.00, alpha: 1.0)
        case .completed:          return NSColor(red: 0.30, green: 0.69, blue: 0.31, alpha: 1.0)
        case .error:              return NSColor(red: 0.96, green: 0.26, blue: 0.21, alpha: 1.0)
        }
    }

    /// Face feature color (darker shade of body)
    var faceColor: NSColor {
        switch self {
        case .idle:               return NSColor(red: 0.40, green: 0.40, blue: 0.40, alpha: 1.0)
        case .running:            return NSColor(red: 0.42, green: 0.23, blue: 0.18, alpha: 1.0)
        case .permissionRequired: return NSColor(red: 0.60, green: 0.42, blue: 0.00, alpha: 1.0)
        case .completed:          return NSColor(red: 0.18, green: 0.49, blue: 0.20, alpha: 1.0)
        case .error:              return NSColor(red: 0.60, green: 0.16, blue: 0.13, alpha: 1.0)
        }
    }

    var label: String {
        switch self {
        case .idle: return "대기중"
        case .running: return "작업중"
        case .permissionRequired: return "승인 필요"
        case .completed: return "완료"
        case .error: return "오류"
        }
    }

    var priority: Int {
        switch self {
        case .idle: return 0
        case .running: return 1
        case .completed: return 2
        case .error: return 3
        case .permissionRequired: return 4
        }
    }
}

struct SessionStatus: Codable, Identifiable {
    let sessionId: String
    let status: ClaudeStatus
    let timestamp: String
    let message: String
    let cwd: String

    var id: String { sessionId }

    var projectName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    var timeString: String {
        let parts = timestamp.split(separator: "T")
        if parts.count >= 2 {
            let timePart = parts[1]
            let timeComponents = timePart.split(separator: ":")
            if timeComponents.count >= 2 {
                return "\(timeComponents[0]):\(timeComponents[1])"
            }
        }
        return ""
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case status, timestamp, message, cwd
    }
}

struct RateLimitWindow: Codable {
    let usedPercentage: Double?
    let resetsAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }

    var resetTimeString: String? {
        guard let resets = resetsAt else { return nil }
        let remaining = resets - Date().timeIntervalSince1970
        guard remaining > 0 else { return nil }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
    }
}

struct UsageInfo: Codable {
    let fiveHour: RateLimitWindow?
    let sevenDay: RateLimitWindow?
    let model: String?
    let updatedAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case model
        case updatedAt = "updated_at"
    }

    var isStale: Bool {
        guard let updated = updatedAt else { return true }
        return Date().timeIntervalSince1970 - updated > 600
    }
}

class StatusModel: ObservableObject {
    @Published var sessions: [SessionStatus] = []
    @Published private(set) var animationFrame: Int = 0
    @Published var usageInfo: UsageInfo?
    @Published var showUsageInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showUsageInMenuBar, forKey: "showUsageInMenuBar") }
    }
    @Published var showResetTimeInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showResetTimeInMenuBar, forKey: "showResetTimeInMenuBar") }
    }

    private let sessionsDirectory: URL
    private let usageFile: URL
    private let loadQueue = DispatchQueue(label: "com.claude.statusbar.load", qos: .utility)
    private var fileDescriptor: Int32 = -1
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var pollingTimer: DispatchSourceTimer?
    private var animationTimer: Timer?
    private var workspaceObserver: Any?
    private var completedSince: Date?

    private static let terminalBundleIds: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "org.alacritty",
        "net.kovidgoyal.kitty",
        "com.mitchellh.ghostty",
        "co.zeit.hyper",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",  // Cursor
    ]

    var aggregatedStatus: ClaudeStatus {
        guard !sessions.isEmpty else { return .idle }
        return sessions.max(by: { $0.status.priority < $1.status.priority })?.status ?? .idle
    }

    var activeSessionCount: Int {
        sessions.count
    }

    var menuBarIcon: NSImage {
        ClaudeIcon.render(for: aggregatedStatus, frame: animationFrame)
    }

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        sessionsDirectory = home.appendingPathComponent(".claude-status/sessions")
        usageFile = home.appendingPathComponent(".claude-status/usage.json")
        showUsageInMenuBar = UserDefaults.standard.object(forKey: "showUsageInMenuBar") as? Bool ?? false
        showResetTimeInMenuBar = UserDefaults.standard.object(forKey: "showResetTimeInMenuBar") as? Bool ?? false
        ensureDirectoryExists()
        performFirstLaunchSetupIfNeeded()
        loadSessions()
        loadUsage()
        startWatching()
        startWatchingTerminalFocus()
    }

    deinit {
        stopWatching()
    }

    private func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(
            at: sessionsDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Performs first-launch setup: copies bundled resources and configures Claude hooks.
    /// Only runs once; controlled by a flag file at ~/.claude-status/.installed
    private func performFirstLaunchSetupIfNeeded() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let statusDir = home.appendingPathComponent(".claude-status")
        let installedFlag = statusDir.appendingPathComponent(".installed")

        // Skip if already installed
        if fm.fileExists(atPath: installedFlag.path) { return }

        // 1. Create directories
        let scriptsDir = statusDir.appendingPathComponent("scripts")
        let sessionsDir = statusDir.appendingPathComponent("sessions")
        try? fm.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

        // 2. Copy bundled resources from app bundle
        guard let resourcePath = Bundle.main.resourcePath else { return }
        let resourceDir = URL(fileURLWithPath: resourcePath)

        // Copy update-status.sh script
        let srcScript = resourceDir.appendingPathComponent("update-status.sh")
        let dstScript = scriptsDir.appendingPathComponent("update-status.sh")
        if fm.fileExists(atPath: srcScript.path) {
            try? fm.removeItem(at: dstScript)
            try? fm.copyItem(at: srcScript, to: dstScript)
            // Make executable
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dstScript.path)
        }

        // Copy icon images as status-specific names
        // running.png → icon-running.png
        // coffee3.png → icon-completed.png, icon-permission_required.png, icon-error.png
        let imageMapping: [(source: String, dest: String)] = [
            ("running.png", "icon-running.png"),
            ("coffee3.png", "icon-completed.png"),
            ("coffee3.png", "icon-permission_required.png"),
            ("coffee3.png", "icon-error.png"),
        ]
        for mapping in imageMapping {
            let src = resourceDir.appendingPathComponent(mapping.source)
            let dst = statusDir.appendingPathComponent(mapping.dest)
            if fm.fileExists(atPath: src.path) {
                try? fm.removeItem(at: dst)
                try? fm.copyItem(at: src, to: dst)
            }
        }

        // 3. Configure hooks in ~/.claude/settings.json (merge, don't overwrite)
        configureClaudeHooks()

        // 4. Write flag file
        try? "".write(to: installedFlag, atomically: true, encoding: .utf8)
    }

    /// Merges ClaudeStatusBar hook configuration into ~/.claude/settings.json
    /// without overwriting existing settings.
    private func configureClaudeHooks() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let claudeDir = home.appendingPathComponent(".claude")
        let settingsFile = claudeDir.appendingPathComponent("settings.json")

        // Ensure ~/.claude/ exists
        try? fm.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        // Load the hooks template from bundled settings.sample.json
        guard let resourcePath = Bundle.main.resourcePath else { return }
        let sampleFile = URL(fileURLWithPath: resourcePath).appendingPathComponent("settings.sample.json")
        guard let sampleData = try? Data(contentsOf: sampleFile),
              let sampleJson = try? JSONSerialization.jsonObject(with: sampleData) as? [String: Any],
              let newHooks = sampleJson["hooks"] as? [String: Any] else { return }

        // Load existing settings or start fresh
        var settings: [String: Any] = [:]
        if fm.fileExists(atPath: settingsFile.path),
           let existingData = try? Data(contentsOf: settingsFile),
           let existingJson = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            settings = existingJson
        }

        // Merge hooks: for each hook event, append our entries to existing arrays
        // Check if our hooks are already present (prevent duplicates on re-install)
        var existingHooks = settings["hooks"] as? [String: Any] ?? [:]
        let marker = "update-status.sh"
        for (eventName, newEntries) in newHooks {
            guard let newArray = newEntries as? [Any] else { continue }
            if let existingArray = existingHooks[eventName] as? [[String: Any]] {
                // Skip if our hooks are already registered
                let alreadyExists = existingArray.contains { entry in
                    if let hooks = entry["hooks"] as? [[String: Any]] {
                        return hooks.contains { ($0["command"] as? String)?.contains(marker) == true }
                    }
                    return false
                }
                if alreadyExists { continue }
                existingHooks[eventName] = existingArray + (newArray as? [[String: Any]] ?? [])
            } else {
                existingHooks[eventName] = newArray
            }
        }
        settings["hooks"] = existingHooks

        // Write back
        if let outputData = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
            try? outputData.write(to: settingsFile, options: .atomic)
        }
    }

    func loadSessions() {
        loadQueue.async { [weak self] in
            self?.doLoadSessions()
        }
    }

    private func loadUsage() {
        loadQueue.async { [weak self] in
            self?.doLoadUsage()
        }
    }

    private func doLoadUsage() {
        guard let data = try? Data(contentsOf: usageFile),
              let info = try? JSONDecoder().decode(UsageInfo.self, from: data),
              !info.isStale else {
            DispatchQueue.main.async { [weak self] in
                self?.usageInfo = nil
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.usageInfo = info
        }
    }

    private func doLoadSessions() {
        let fm = FileManager.default
        // Issue #16: On failure, retain existing sessions instead of clearing
        guard let files = try? fm.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return
        }

        let now = Date()
        let staleThreshold: TimeInterval = 24 * 60 * 60

        var loaded: [SessionStatus] = []

        for file in files where file.pathExtension == "json" {
            // Skip temp files from atomic writes
            if file.lastPathComponent.hasPrefix(".tmp.") { continue }

            if let attrs = try? fm.attributesOfItem(atPath: file.path),
               let modDate = attrs[.modificationDate] as? Date,
               now.timeIntervalSince(modDate) > staleThreshold {
                try? fm.removeItem(at: file)
                continue
            }

            guard let data = try? Data(contentsOf: file),
                  let session = try? JSONDecoder().decode(SessionStatus.self, from: data) else {
                continue
            }

            loaded.append(session)
        }

        loaded.sort { $0.status.priority > $1.status.priority }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.playAlertIfNeeded(old: self.sessions, new: loaded)
            self.sessions = loaded
            self.updateAnimation()
        }
    }

    private func playAlertIfNeeded(old: [SessionStatus], new: [SessionStatus]) {
        let alertStatuses: Set<ClaudeStatus> = [.completed, .permissionRequired]
        let oldMap = Dictionary(old.map { ($0.sessionId, $0.status) }, uniquingKeysWith: { _, new in new })
        for session in new where alertStatuses.contains(session.status) {
            if oldMap[session.sessionId] != session.status {
                NSSound(named: .init("Funk"))?.play()
                return  // one sound per update
            }
        }
    }

    private func updateAnimation() {
        let status = aggregatedStatus

        // Track when completed state started
        if status == .completed {
            if completedSince == nil { completedSince = Date() }
        } else {
            completedSince = nil
        }

        // Stop blinking completed after 3 minutes
        let completedExpired = status == .completed &&
            completedSince != nil &&
            Date().timeIntervalSince(completedSince!) > 180

        let shouldAnimate = (status == .permissionRequired) ||
                            (status == .completed && !completedExpired)

        if shouldAnimate && animationTimer == nil {
            animationTimer = Timer.scheduledTimer(
                withTimeInterval: 0.5,
                repeats: true
            ) { [weak self] _ in
                guard let self = self else { return }
                self.animationFrame = (self.animationFrame + 1) % 2
            }
        } else if !shouldAnimate {
            animationTimer?.invalidate()
            animationTimer = nil
            animationFrame = 0
        }
    }

    private func startWatching() {
        setupDirectoryWatcher()

        // Reliable fallback timer (RunLoop-independent)
        let timer = DispatchSource.makeTimerSource(queue: loadQueue)
        timer.schedule(deadline: .now() + 2.0, repeating: 2.0)
        timer.setEventHandler { [weak self] in
            self?.doLoadSessions()
            self?.doLoadUsage()
            // Dismiss completed sessions when terminal is already active,
            // since didActivateApplicationNotification won't fire again.
            DispatchQueue.main.async {
                guard let self = self,
                      let activeApp = NSWorkspace.shared.frontmostApplication,
                      let bundleId = activeApp.bundleIdentifier,
                      StatusModel.terminalBundleIds.contains(bundleId) else { return }
                self.dismissCompletedSessions()
            }
        }
        timer.resume()
        pollingTimer = timer
    }

    /// Sets up DispatchSource to watch the sessions directory.
    /// Re-establishes the watcher if the directory is deleted and recreated (#17).
    private func setupDirectoryWatcher() {
        // Cancel existing watcher
        dispatchSource?.cancel()
        dispatchSource = nil

        ensureDirectoryExists()
        let path = sessionsDirectory.path
        let fd = path.withCString { cPath in
            Darwin.open(cPath, O_EVTONLY)
        }
        guard fd >= 0 else { return }

        fileDescriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .attrib, .link],
            queue: loadQueue
        )
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let data = source.data
            // If directory was deleted, re-establish watcher
            if data.contains(.delete) || data.contains(.rename) {
                self.ensureDirectoryExists()
                self.setupDirectoryWatcher()
            }
            self.doLoadSessions()
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        source.resume()
        dispatchSource = source
    }

    private func startWatchingTerminalFocus() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleId = app.bundleIdentifier,
                  StatusModel.terminalBundleIds.contains(bundleId) else { return }
            self?.dismissCompletedSessions()
        }
    }

    private static let dismissableStatuses: Set<ClaudeStatus> = [.completed, .error]

    private func dismissCompletedSessions() {
        loadQueue.async { [weak self] in
            guard let self = self else { return }
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(at: self.sessionsDirectory, includingPropertiesForKeys: nil) else { return }
            var dismissed = false
            for file in files where file.pathExtension == "json" {
                // Read, check, re-read before delete to avoid TOCTOU race (#6)
                guard let data = try? Data(contentsOf: file),
                      let session = try? JSONDecoder().decode(SessionStatus.self, from: data),
                      StatusModel.dismissableStatuses.contains(session.status) else { continue }
                // Re-read to confirm status hasn't changed (e.g., hook wrote 'running' in between)
                guard let data2 = try? Data(contentsOf: file),
                      let session2 = try? JSONDecoder().decode(SessionStatus.self, from: data2),
                      StatusModel.dismissableStatuses.contains(session2.status) else { continue }
                try? fm.removeItem(at: file)
                dismissed = true
            }
            if dismissed { self.doLoadSessions() }
        }
    }

    private func stopWatching() {
        dispatchSource?.cancel()
        dispatchSource = nil
        pollingTimer?.cancel()
        pollingTimer = nil
        animationTimer?.invalidate()
        animationTimer = nil
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        fileDescriptor = -1
    }

    func resetAllSessions() {
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: nil
        ) {
            for file in files where file.pathExtension == "json" {
                try? fm.removeItem(at: file)
            }
        }
        loadSessions()
    }

    func resetSession(id: String) {
        let file = sessionsDirectory.appendingPathComponent("\(id).json")
        try? FileManager.default.removeItem(at: file)
        loadSessions()
    }

    func focusSession(_ session: SessionStatus) {
        // Dismiss completed/error sessions immediately on focus,
        // since didActivateApplicationNotification may not fire
        // when the terminal is already the active app.
        // Re-read file to avoid race: hook may have changed status to running
        // between the last UI refresh and this click.
        if session.status == .completed || session.status == .error {
            let file = sessionsDirectory.appendingPathComponent("\(session.sessionId).json")
            if let data = try? Data(contentsOf: file),
               let current = try? JSONDecoder().decode(SessionStatus.self, from: data),
               StatusModel.dismissableStatuses.contains(current.status) {
                try? FileManager.default.removeItem(at: file)
                loadSessions()
            }
        }

        let cwd = session.cwd

        // Try CLI tools that can focus an existing window for the given directory
        let cliCandidates = ["/usr/local/bin/cursor", "/usr/local/bin/code"]
        for cli in cliCandidates {
            if FileManager.default.isExecutableFile(atPath: cli) {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: cli)
                task.arguments = [cwd]
                try? task.run()
                return
            }
        }

        // Fallback: activate terminal app via AppleScript
        let script = """
        tell application "System Events"
            set termApps to {"Terminal", "iTerm2", "Warp", "Ghostty", "Alacritty", "kitty", "Cursor", "Visual Studio Code"}
            repeat with appName in termApps
                if exists (process appName) then
                    tell process appName to set frontmost to true
                    return
                end if
            end repeat
        end tell
        """
        let appleScript = NSAppleScript(source: script)
        appleScript?.executeAndReturnError(nil)
    }

    func openStatusDirectory() {
        NSWorkspace.shared.open(sessionsDirectory)
    }

    func openClaudeSettings() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settingsFile = home.appendingPathComponent(".claude/settings.json")
        NSWorkspace.shared.open(settingsFile)
    }
}
