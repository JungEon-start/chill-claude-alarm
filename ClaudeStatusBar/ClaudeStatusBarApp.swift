import SwiftUI

@main
struct ClaudeStatusBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var statusModel = StatusModel()
    private let updater = Updater()

    init() {
        StartupDiagnostics.log("app init")
        // Delay updater start so first launch state is visible to users.
        let updater = self.updater
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            updater.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            StatusMenuView(model: statusModel)
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: statusModel.menuBarIcon)
                if let fiveHour = statusModel.usageInfo?.fiveHour {
                    let showPct = statusModel.showUsageInMenuBar && fiveHour.usedPercentage != nil
                    let showTime = statusModel.showResetTimeInMenuBar
                        && fiveHour.resetsAt != nil
                        && (fiveHour.resetsAt! - Date().timeIntervalSince1970) > 0

                    if showPct || showTime {
                        let parts = [
                            showPct ? "\(Int(fiveHour.usedPercentage!))%" : nil,
                            showTime ? {
                                let r = fiveHour.resetsAt! - Date().timeIntervalSince1970
                                return "\(Int(r) / 3600)h\((Int(r) % 3600) / 60)m"
                            }() : nil
                        ].compactMap { $0 }.joined(separator: " ")

                        Text(parts)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                    }
                }
            }
        }
    }
}
