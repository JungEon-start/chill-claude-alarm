import SwiftUI

@main
struct ClaudeStatusBarApp: App {
    @StateObject private var statusModel = StatusModel()

    var body: some Scene {
        MenuBarExtra {
            StatusMenuView(model: statusModel)
        } label: {
            Image(nsImage: statusModel.menuBarIcon)
        }
    }
}
