import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let bundleID = "com.claude.statusbar"
    private let appName = "Chill Claude"

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        StartupDiagnostics.log("willFinishLaunching pid=\(ProcessInfo.processInfo.processIdentifier) path=\(Bundle.main.bundleURL.path)")

        if handOffToRunningInstanceIfNeeded() {
            return
        }

        cleanupDuplicateInstallIfNeeded()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        StartupDiagnostics.log("didFinishLaunching")
    }

    private func handOffToRunningInstanceIfNeeded() -> Bool {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != currentPID }

        guard let existing = running.first else {
            return false
        }

        StartupDiagnostics.log("found existing instance pid=\(existing.processIdentifier); handing off and terminating duplicate")
        existing.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
        return true
    }

    private func cleanupDuplicateInstallIfNeeded() {
        // Skip dedup when running from development/build paths.
        let currentPath = canonicalPath(Bundle.main.bundleURL)
        guard currentPath.hasSuffix("/Applications/\(appName).app") else {
            StartupDiagnostics.log("skip duplicate cleanup for non-installed path=\(currentPath)")
            return
        }

        let fm = FileManager.default
        let statusDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude-status")
        let marker = statusDir.appendingPathComponent(".dedup-v1.done")
        if fm.fileExists(atPath: marker.path) {
            StartupDiagnostics.log("duplicate cleanup already completed")
            return
        }

        try? fm.createDirectory(at: statusDir, withIntermediateDirectories: true)

        let candidates = [
            URL(fileURLWithPath: "/Applications/\(appName).app"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications/\(appName).app"),
        ]

        for appURL in candidates {
            let path = canonicalPath(appURL)
            guard path != currentPath else { continue }
            guard fm.fileExists(atPath: path) else { continue }

            StartupDiagnostics.log("found duplicate app path=\(path); moving to Trash and unregistering")
            NSWorkspace.shared.recycle([appURL]) { _, error in
                if let error {
                    StartupDiagnostics.log("failed to recycle duplicate path=\(path) error=\(error.localizedDescription)")
                } else {
                    StartupDiagnostics.log("recycled duplicate path=\(path)")
                }
            }
            unregisterFromLaunchServices(path: path)
        }

        try? "".write(to: marker, atomically: true, encoding: .utf8)
        StartupDiagnostics.log("duplicate cleanup marker written")
    }

    private func unregisterFromLaunchServices(path: String) {
        let lsregister = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
        guard FileManager.default.isExecutableFile(atPath: lsregister) else { return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: lsregister)
        task.arguments = ["-u", path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            StartupDiagnostics.log("lsregister -u finished for \(path) code=\(task.terminationStatus)")
        } catch {
            StartupDiagnostics.log("lsregister -u failed for \(path) error=\(error.localizedDescription)")
        }
    }

    private func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
