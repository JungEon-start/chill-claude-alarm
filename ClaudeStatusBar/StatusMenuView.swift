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

        if let usage = model.usageInfo {
            Divider()
            usageSection(usage)
        }

        Divider()

        Toggle("상태바에 사용량 표시", isOn: $model.showUsageInMenuBar)
        Toggle("상태바에 초기화 시간 표시", isOn: $model.showResetTimeInMenuBar)

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        Text("Chill Claude v\(version)")
            .font(.footnote)
            .foregroundColor(.secondary)

        Button("종료") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private func usageSection(_ usage: UsageInfo) -> some View {
        if let fiveHour = usage.fiveHour, let used = fiveHour.usedPercentage {
            let icon = quotaIcon(used: used)
            let resetStr = fiveHour.resetTimeString.map { " (\($0) 후 초기화)" } ?? ""
            Text("\(icon) 5시간: \(Int(used))% 사용\(resetStr)")
                .font(.footnote)
        }
        if let sevenDay = usage.sevenDay, let used = sevenDay.usedPercentage {
            let icon = quotaIcon(used: used)
            let resetStr = sevenDay.resetTimeString.map { " (\($0) 후 초기화)" } ?? ""
            Text("\(icon) 7일: \(Int(used))% 사용\(resetStr)")
                .font(.footnote)
        }
    }

    private func quotaIcon(used: Double) -> String {
        if used < 50 { return "\u{1F7E2}" }
        if used < 75 { return "\u{1F7E1}" }
        return "\u{1F534}"
    }
}
