import SwiftUI

@main
struct ClaudeStatusBarApp: App {
    @StateObject private var statusModel = StatusModel()
    private let updater = Updater()

    init() {
        updater.start()
    }

    var body: some Scene {
        MenuBarExtra {
            StatusMenuView(model: statusModel)
        } label: {
            Image(nsImage: statusModel.menuBarIcon)
        }
    }
}
