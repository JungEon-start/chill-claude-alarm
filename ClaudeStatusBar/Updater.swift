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
    private static let appBundleName = "Chill Claude.app"
    private static let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

    private var timer: DispatchSourceTimer?

    func start() {
        StartupDiagnostics.log("updater start")
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
        if now - lastCheck < Updater.checkInterval {
            StartupDiagnostics.log("skip update check (cooldown)")
            return
        }

        UserDefaults.standard.set(now, forKey: Updater.lastCheckKey)
        StartupDiagnostics.log("checking for updates")
        checkForUpdate()
    }

    private func checkForUpdate() {
        guard let url = URL(string: Updater.apiURL) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error {
                StartupDiagnostics.log("update check network error: \(error.localizedDescription)")
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
                StartupDiagnostics.log("update check HTTP \(http.statusCode)")
                return
            }
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let assets = json["assets"] as? [[String: Any]] else { return }

            let remoteVersion = tagName.replacingOccurrences(of: "v", with: "")
            let localVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

            guard self?.isNewer(remote: remoteVersion, local: localVersion) == true else {
                StartupDiagnostics.log("no update needed local=\(localVersion) remote=\(remoteVersion)")
                return
            }
            StartupDiagnostics.log("update available local=\(localVersion) remote=\(remoteVersion)")

            // Find the zip asset
            guard let asset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
                  let downloadURL = asset["browser_download_url"] as? String else {
                StartupDiagnostics.log("update zip asset not found")
                return
            }

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
        StartupDiagnostics.log("start downloading update version=\(version)")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChillClaudeUpdate-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let zipPath = tempDir.appendingPathComponent("ChillClaude.zip")

        // Download
        URLSession.shared.downloadTask(with: downloadURL) { [weak self] location, _, error in
            guard let location = location, error == nil else {
                StartupDiagnostics.log("update download failed: \(error?.localizedDescription ?? "unknown")")
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
                    StartupDiagnostics.log("unzip failed with code \(unzip.terminationStatus)")
                    try? FileManager.default.removeItem(at: tempDir)
                    return
                }

                guard let newApp = self?.findAppBundle(in: tempDir) else {
                    StartupDiagnostics.log("could not find .app in extracted update")
                    try? FileManager.default.removeItem(at: tempDir)
                    return
                }
                StartupDiagnostics.log("found update app at \(newApp.path)")

                self?.replaceAndRelaunch(newApp: newApp, tempDir: tempDir)
            } catch {
                StartupDiagnostics.log("update install failed: \(error.localizedDescription)")
                try? FileManager.default.removeItem(at: tempDir)
            }
        }.resume()
    }

    private static func shellEscape(_ s: String) -> String {
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func replaceAndRelaunch(newApp: URL, tempDir: URL) {
        guard let currentApp = Bundle.main.bundleURL as URL? else { return }
        let pid = ProcessInfo.processInfo.processIdentifier

        let sCurrent = Updater.shellEscape(currentApp.path)
        let sNew = Updater.shellEscape(newApp.path)
        let sTemp = Updater.shellEscape(tempDir.path)

        // Shell script: wait for current app to quit, replace, relaunch, cleanup
        let script = """
        #!/bin/bash
        set -euo pipefail
        while kill -0 \(pid) 2>/dev/null; do sleep 0.5; done

        for p in "/Applications/\(Updater.appBundleName)" "$HOME/Applications/\(Updater.appBundleName)"; do
            if [ "$p" != \(sCurrent) ] && [ -d "$p" ]; then
                rm -rf "$p" || true
            fi
        done

        rm -rf \(sCurrent)
        mv \(sNew) \(sCurrent)
        if [ -x "\(Updater.lsregisterPath)" ]; then
            "\(Updater.lsregisterPath)" -f \(sCurrent) >/dev/null 2>&1 || true
        fi
        open -n \(sCurrent) || (sleep 1 && open -n \(sCurrent))
        rm -rf \(sTemp)
        """

        let scriptPath = tempDir.appendingPathComponent("update.sh")
        do {
            try script.write(to: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)
        } catch {
            StartupDiagnostics.log("failed to write update script: \(error.localizedDescription)")
            return
        }

        // Launch the update script and quit
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptPath.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            StartupDiagnostics.log("update script launched, terminating current app")
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            StartupDiagnostics.log("failed to launch update script: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    private func findAppBundle(in directory: URL) -> URL? {
        let fm = FileManager.default
        if let direct = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first(where: {
            $0.lastPathComponent == Updater.appBundleName
        }) {
            return direct
        }

        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: keys) else {
            return nil
        }

        var firstMatch: URL?
        for case let url as URL in enumerator {
            guard url.pathExtension == "app" else { continue }
            if url.lastPathComponent == Updater.appBundleName {
                return url
            }
            if firstMatch == nil {
                firstMatch = url
            }
        }
        return firstMatch
    }
}
