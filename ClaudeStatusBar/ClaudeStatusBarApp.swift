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
                // 5-hour window while it is live; falls back to the 7-day
                // window when there is no 5-hour limit.
                if let text = statusModel.usageInfo?.menuBarText(
                    showPercent: statusModel.showUsageInMenuBar,
                    showResetTime: statusModel.showResetTimeInMenuBar
                ) {
                    Text(text)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
            }
        }
    }
}
