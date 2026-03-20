import SwiftUI

struct StatusMenuView: View {
    @ObservedObject var model: StatusModel

    var body: some View {
        if model.sessions.isEmpty {
            Text("활성 세션 없음")
        } else {
            ForEach(model.sessions) { session in
                Button {
                    model.focusSession(session)
                } label: {
                    Text("\(session.status.emoji) \(session.projectName)  \(session.status.label)  (\(session.timeString))")
                }
            }
        }

        Divider()

        Button("종료") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
