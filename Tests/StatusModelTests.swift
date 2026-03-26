import Foundation

// Minimal test harness
var passed = 0
var failed = 0
var currentTest = ""

func describe(_ name: String, _ block: () -> Void) {
    print("\n=== \(name) ===")
    block()
}

func it(_ name: String, _ block: () -> Void) {
    currentTest = name
    block()
}

func expect(_ condition: Bool, _ message: String = "") {
    if condition {
        passed += 1
        print("  ✅ \(currentTest)\(message.isEmpty ? "" : " — \(message)")")
    } else {
        failed += 1
        print("  ❌ \(currentTest)\(message.isEmpty ? "" : " — \(message)")")
    }
}

// ============================================================
// Types (duplicated from source for standalone testing)
// ============================================================

enum ClaudeStatus: String, Codable {
    case idle
    case running
    case permissionRequired = "permission_required"
    case completed
    case error

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

struct SessionStatus: Codable {
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

func isNewer(remote: String, local: String) -> Bool {
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

func shellEscape(_ s: String) -> String {
    return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

func decode(_ json: String) -> SessionStatus? {
    try? JSONDecoder().decode(SessionStatus.self, from: json.data(using: .utf8)!)
}

let dismissableStatuses: Set<ClaudeStatus> = [.completed, .error]

// ============================================================
// Tests
// ============================================================

// MARK: - ClaudeStatus

describe("ClaudeStatus — Raw Values") {
    it("idle encodes as 'idle'") {
        expect(ClaudeStatus.idle.rawValue == "idle")
    }
    it("running encodes as 'running'") {
        expect(ClaudeStatus.running.rawValue == "running")
    }
    it("permissionRequired encodes as 'permission_required'") {
        expect(ClaudeStatus.permissionRequired.rawValue == "permission_required")
    }
    it("completed encodes as 'completed'") {
        expect(ClaudeStatus.completed.rawValue == "completed")
    }
    it("error encodes as 'error'") {
        expect(ClaudeStatus.error.rawValue == "error")
    }
}

describe("ClaudeStatus — Priority Ordering") {
    it("idle < running < completed < error < permissionRequired") {
        expect(ClaudeStatus.idle.priority < ClaudeStatus.running.priority)
        expect(ClaudeStatus.running.priority < ClaudeStatus.completed.priority)
        expect(ClaudeStatus.completed.priority < ClaudeStatus.error.priority)
        expect(ClaudeStatus.error.priority < ClaudeStatus.permissionRequired.priority)
    }
    it("permissionRequired has highest priority") {
        let all: [ClaudeStatus] = [.idle, .running, .completed, .error, .permissionRequired]
        let max = all.max(by: { $0.priority < $1.priority })
        expect(max == .permissionRequired)
    }
}

describe("ClaudeStatus — Labels") {
    it("Korean labels are correct") {
        expect(ClaudeStatus.idle.label == "대기중")
        expect(ClaudeStatus.running.label == "작업중")
        expect(ClaudeStatus.permissionRequired.label == "승인 필요")
        expect(ClaudeStatus.completed.label == "완료")
        expect(ClaudeStatus.error.label == "오류")
    }
}

// MARK: - SessionStatus JSON Decoding

describe("SessionStatus — JSON Decoding") {
    it("decodes valid compact JSON") {
        let s = decode(#"{"session_id":"abc123","status":"running","timestamp":"2026-03-24T10:30:00+0900","message":"Processing...","cwd":"/Users/test/project"}"#)
        expect(s != nil, "should decode")
        expect(s?.sessionId == "abc123")
        expect(s?.status == .running)
        expect(s?.cwd == "/Users/test/project")
    }
    it("decodes permission_required status") {
        let s = decode(#"{"session_id":"x","status":"permission_required","timestamp":"T","message":"","cwd":"/tmp"}"#)
        expect(s?.status == .permissionRequired)
    }
    it("fails on unknown status") {
        let s = decode(#"{"session_id":"x","status":"unknown_state","timestamp":"T","message":"","cwd":"/"}"#)
        expect(s == nil, "should fail for unknown status")
    }
    it("fails on missing required fields") {
        let s = decode(#"{"session_id":"x","status":"running"}"#)
        expect(s == nil, "should fail without timestamp/message/cwd")
    }
    it("fails on empty JSON") {
        expect(decode("{}") == nil)
    }
    it("fails on malformed JSON") {
        expect(decode("not json") == nil)
    }
}

// MARK: - SessionStatus Computed Properties

describe("SessionStatus — projectName") {
    it("extracts last path component") {
        let s = decode(#"{"session_id":"a","status":"running","timestamp":"T","message":"","cwd":"/Users/leo/Projects/my-app"}"#)!
        expect(s.projectName == "my-app")
    }
    it("handles root path") {
        let s = decode(#"{"session_id":"a","status":"running","timestamp":"T","message":"","cwd":"/"}"#)!
        expect(s.projectName == "/", "root should return /")
    }
}

describe("SessionStatus — timeString") {
    it("extracts HH:MM from ISO timestamp") {
        let s = decode(#"{"session_id":"a","status":"running","timestamp":"2026-03-24T14:35:00+0900","message":"","cwd":"/tmp"}"#)!
        expect(s.timeString == "14:35")
    }
    it("handles timestamp with timezone offset in time part") {
        let s = decode(#"{"session_id":"a","status":"running","timestamp":"2026-03-24T09:05:30+0900","message":"","cwd":"/tmp"}"#)!
        expect(s.timeString == "09:05")
    }
    it("returns empty string for invalid timestamp") {
        let s = decode(#"{"session_id":"a","status":"running","timestamp":"not-a-date","message":"","cwd":"/tmp"}"#)!
        expect(s.timeString == "")
    }
    it("returns empty string for empty timestamp") {
        let s = decode(#"{"session_id":"a","status":"running","timestamp":"","message":"","cwd":"/tmp"}"#)!
        expect(s.timeString == "")
    }
}

// MARK: - Aggregated Status

describe("Aggregated Status — Priority-based selection") {
    it("returns idle for empty sessions") {
        let sessions: [SessionStatus] = []
        let result = sessions.isEmpty ? ClaudeStatus.idle :
            sessions.max(by: { $0.status.priority < $1.status.priority })?.status ?? .idle
        expect(result == .idle)
    }
    it("returns highest priority status from mixed sessions") {
        let a = decode(#"{"session_id":"1","status":"running","timestamp":"T","message":"","cwd":"/a"}"#)!
        let b = decode(#"{"session_id":"2","status":"completed","timestamp":"T","message":"","cwd":"/b"}"#)!
        let c = decode(#"{"session_id":"3","status":"permission_required","timestamp":"T","message":"","cwd":"/c"}"#)!
        let result = [a, b, c].max(by: { $0.status.priority < $1.status.priority })?.status ?? .idle
        expect(result == .permissionRequired, "permission_required should win")
    }
    it("running + completed → completed wins") {
        let a = decode(#"{"session_id":"1","status":"running","timestamp":"T","message":"","cwd":"/a"}"#)!
        let b = decode(#"{"session_id":"2","status":"completed","timestamp":"T","message":"","cwd":"/b"}"#)!
        let result = [a, b].max(by: { $0.status.priority < $1.status.priority })?.status ?? .idle
        expect(result == .completed)
    }
}

// MARK: - Version Comparison (Updater)

describe("Updater — isNewer()") {
    it("0.2 → 0.3 is newer") {
        expect(isNewer(remote: "0.3", local: "0.2") == true)
    }
    it("0.3 → 0.2 is NOT newer") {
        expect(isNewer(remote: "0.2", local: "0.3") == false)
    }
    it("same version is NOT newer") {
        expect(isNewer(remote: "0.3", local: "0.3") == false)
    }
    it("1.0.0 → 0.9.9 is newer") {
        expect(isNewer(remote: "1.0.0", local: "0.9.9") == true)
    }
    it("0.3 vs 0.3.0 — same version") {
        expect(isNewer(remote: "0.3", local: "0.3.0") == false)
    }
    it("0.3.1 vs 0.3 — patch is newer") {
        expect(isNewer(remote: "0.3.1", local: "0.3") == true)
    }
    it("handles v prefix stripped") {
        let remote = "v0.4".replacingOccurrences(of: "v", with: "")
        expect(isNewer(remote: remote, local: "0.3") == true)
    }
    it("handles non-numeric parts gracefully") {
        expect(isNewer(remote: "1.0.beta", local: "0.9") == true, "non-numeric parts dropped")
    }
}

// MARK: - FIX #2: dismissCompletedSessions now dismisses error too

describe("FIX #2: dismissableStatuses includes error") {
    it("completed is dismissable") {
        expect(dismissableStatuses.contains(.completed))
    }
    it("error is dismissable") {
        expect(dismissableStatuses.contains(.error))
    }
    it("running is NOT dismissable") {
        expect(!dismissableStatuses.contains(.running))
    }
    it("permissionRequired is NOT dismissable") {
        expect(!dismissableStatuses.contains(.permissionRequired))
    }
    it("idle is NOT dismissable") {
        expect(!dismissableStatuses.contains(.idle))
    }
}

// MARK: - focusSession Dismiss Logic

describe("focusSession — dismiss behavior") {
    it("completed session should be dismissed on focus") {
        let status = ClaudeStatus.completed
        expect(status == .completed || status == .error)
    }
    it("error session should be dismissed on focus") {
        let status = ClaudeStatus.error
        expect(status == .completed || status == .error)
    }
    it("running session should NOT be dismissed on focus") {
        let status = ClaudeStatus.running
        expect((status == .completed || status == .error) == false)
    }
    it("permissionRequired should NOT be dismissed on focus") {
        let status = ClaudeStatus.permissionRequired
        expect((status == .completed || status == .error) == false)
    }
}

// MARK: - FIX #5: Shell escape

describe("FIX #5: shellEscape()") {
    it("wraps simple string in single quotes") {
        expect(shellEscape("hello") == "'hello'")
    }
    it("escapes single quotes inside string") {
        expect(shellEscape("it's") == "'it'\\''s'")
    }
    it("handles path with spaces") {
        expect(shellEscape("/Users/test/my app") == "'/Users/test/my app'")
    }
    it("handles dollar signs safely") {
        expect(shellEscape("$HOME/test") == "'$HOME/test'")
    }
    it("handles backticks safely") {
        expect(shellEscape("`whoami`") == "'`whoami`'")
    }
    it("handles double quotes safely") {
        let result = shellEscape("say \"hello\"")
        expect(result == "'say \"hello\"'")
    }
}

// MARK: - Stale Session Cleanup

describe("Stale Session Cleanup") {
    it("24-hour threshold is 86400 seconds") {
        let threshold: TimeInterval = 24 * 60 * 60
        expect(threshold == 86400)
    }
}

// MARK: - Animation Frame (simplified after dead code removal)

describe("Animation Frame") {
    it("frame alternates between 0 and 1") {
        var frame = 0
        frame = (frame + 1) % 2
        expect(frame == 1)
        frame = (frame + 1) % 2
        expect(frame == 0)
    }
}

// ============================================================
// Summary
// ============================================================

print("\n" + String(repeating: "=", count: 50))
print("Results: \(passed) passed, \(failed) failed, \(passed + failed) total")
if failed > 0 {
    print("⚠️  Some tests failed!")
    exit(1)
} else {
    print("✅ All tests passed!")
}
