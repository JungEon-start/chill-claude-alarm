import Foundation
import AppKit

/// Auto-updater that checks GitHub Releases for new versions.
/// Checks every 8 hours. Downloads and replaces the app automatically.
class Updater {
    // ⚠️ Change this to your public release repo
    static let repoOwner = "JungEon-start"
    static let repoName = "chill-claude-alarm"

    private static let checkInterval: TimeInterval = 8 * 60 * 60  // 8 hours
    private static let lastCheckKey = "lastUpdateCheck"
    private static let apiURL = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"

    private var timer: DispatchSourceTimer?

    func start() {
        // Check on launch if enough time has passed
        checkIfNeeded()

        // Schedule periodic checks
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        t.schedule(deadline: .now() + Updater.checkInterval, repeating: Updater.checkInterval)
        t.setEventHandler { [weak self] in
            self?.checkIfNeeded()
        }
        t.resume()
        timer = t
    }

    private func checkIfNeeded() {
        let lastCheck = UserDefaults.standard.double(forKey: Updater.lastCheckKey)
        let now = Date().timeIntervalSince1970
        if now - lastCheck < Updater.checkInterval { return }

        UserDefaults.standard.set(now, forKey: Updater.lastCheckKey)
        checkForUpdate()
    }

    private func checkForUpdate() {
        guard let url = URL(string: Updater.apiURL) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let assets = json["assets"] as? [[String: Any]] else { return }

            let remoteVersion = tagName.replacingOccurrences(of: "v", with: "")
            let localVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

            guard self?.isNewer(remote: remoteVersion, local: localVersion) == true else { return }

            // Find the zip asset
            guard let asset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
                  let downloadURL = asset["browser_download_url"] as? String else { return }

            self?.downloadAndInstall(url: downloadURL, version: remoteVersion)
        }.resume()
    }

    private func isNewer(remote: String, local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }

    private func downloadAndInstall(url: String, version: String) {
        guard let downloadURL = URL(string: url) else { return }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChillClaudeUpdate-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let zipPath = tempDir.appendingPathComponent("ChillClaude.zip")

        // Download
        URLSession.shared.downloadTask(with: downloadURL) { [weak self] location, _, error in
            guard let location = location, error == nil else {
                try? FileManager.default.removeItem(at: tempDir)
                return
            }

            do {
                try FileManager.default.moveItem(at: location, to: zipPath)

                // Unzip
                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                unzip.arguments = ["-o", zipPath.path, "-d", tempDir.path]
                unzip.standardOutput = FileHandle.nullDevice
                unzip.standardError = FileHandle.nullDevice
                try unzip.run()
                unzip.waitUntilExit()

                guard unzip.terminationStatus == 0 else {
                    try? FileManager.default.removeItem(at: tempDir)
                    return
                }

                // Find the .app in extracted files
                let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                guard let newApp = contents.first(where: { $0.pathExtension == "app" }) else {
                    try? FileManager.default.removeItem(at: tempDir)
                    return
                }

                self?.replaceAndRelaunch(newApp: newApp, tempDir: tempDir)
            } catch {
                try? FileManager.default.removeItem(at: tempDir)
            }
        }.resume()
    }

    private func replaceAndRelaunch(newApp: URL, tempDir: URL) {
        guard let currentApp = Bundle.main.bundleURL as URL? else { return }
        let pid = ProcessInfo.processInfo.processIdentifier

        // Shell script: wait for current app to quit, replace, relaunch, cleanup
        let script = """
        #!/bin/bash
        while kill -0 \(pid) 2>/dev/null; do sleep 0.5; done
        rm -rf "\(currentApp.path)"
        mv "\(newApp.path)" "\(currentApp.path)"
        open "\(currentApp.path)"
        rm -rf "\(tempDir.path)"
        """

        let scriptPath = tempDir.appendingPathComponent("update.sh")
        try? script.write(to: scriptPath, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)

        // Launch the update script and quit
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptPath.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()

        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }
}
