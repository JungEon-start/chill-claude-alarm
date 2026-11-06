import Foundation

struct RateLimitWindow: Codable, Equatable {
    let usedPercentage: Double?
    let resetsAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }

    /// Seconds until this window resets, or nil when unknown or already elapsed.
    func remaining(now: TimeInterval = Date().timeIntervalSince1970) -> TimeInterval? {
        guard let resets = resetsAt else { return nil }
        let remaining = resets - now
        return remaining > 0 ? remaining : nil
    }

    /// Has a usage value and its window has not elapsed yet.
    func isActive(now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard usedPercentage != nil else { return false }
        return resetsAt == nil || remaining(now: now) != nil
    }

    /// Reset countdown for the dropdown menu, e.g. "2d 3h", "4h 12m", "8m".
    func resetTimeString(now: TimeInterval = Date().timeIntervalSince1970) -> String? {
        guard let remaining = remaining(now: now) else { return nil }
        let total = Int(remaining)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
    }

    var resetTimeString: String? { resetTimeString() }
}

struct UsageInfo: Codable, Equatable {
    let fiveHour: RateLimitWindow?
    let sevenDay: RateLimitWindow?
    let model: String?
    let updatedAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case model
        case updatedAt = "updated_at"
    }
}

enum UsageWindowKind: Equatable {
    case fiveHour
    case sevenDay
}

extension UsageInfo {
    /// Which window the menu bar should show.
    /// The 5-hour window wins while it has a live value. When it is missing
    /// (no 5-hour limit reported) or has already reset, fall back to the
    /// 7-day window so the menu bar still shows something meaningful.
    func menuBarWindow(now: TimeInterval = Date().timeIntervalSince1970) -> (kind: UsageWindowKind, window: RateLimitWindow)? {
        if let fiveHour, fiveHour.isActive(now: now) { return (.fiveHour, fiveHour) }
        if let sevenDay, sevenDay.usedPercentage != nil { return (.sevenDay, sevenDay) }
        if let fiveHour, fiveHour.usedPercentage != nil { return (.fiveHour, fiveHour) }
        return nil
    }

    /// Compact menu bar text, e.g. "42% 3h12m" for the 5-hour window or
    /// "48% 2d3h" for the 7-day fallback. Returns nil when nothing to show.
    func menuBarText(showPercent: Bool, showResetTime: Bool,
                     now: TimeInterval = Date().timeIntervalSince1970) -> String? {
        guard showPercent || showResetTime,
              let (_, window) = menuBarWindow(now: now) else { return nil }

        let pct = showPercent ? window.usedPercentage.map { "\(Int($0))%" } : nil
        let time = showResetTime ? window.remaining(now: now).map(UsageInfo.compactDuration) : nil
        guard pct != nil || time != nil else { return nil }

        return [pct, time].compactMap { $0 }.joined(separator: " ")
    }

    /// "2d3h" when a day or more remains, otherwise "3h12m" / "0h8m".
    static func compactDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d\(hours)h" }
        return "\(hours)h\(minutes)m"
    }
}
