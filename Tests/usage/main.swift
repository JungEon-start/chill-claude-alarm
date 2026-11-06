import Foundation

// Compiled together with ClaudeStatusBar/Usage.swift (see Makefile `test`).

var passed = 0
var failed = 0

func check(_ name: String, _ condition: Bool) {
    if condition {
        passed += 1
        print("  ✅ \(name)")
    } else {
        failed += 1
        print("  ❌ \(name)")
    }
}

func eq(_ name: String, _ actual: String?, _ expected: String?) {
    check("\(name) — got \(actual ?? "nil"), want \(expected ?? "nil")", actual == expected)
}

func decode(_ json: String) -> UsageInfo {
    try! JSONDecoder().decode(UsageInfo.self, from: json.data(using: .utf8)!)
}

let now: TimeInterval = 1_800_000_000
let hour: TimeInterval = 3600
let day: TimeInterval = 86400

print("\n=== Menu bar window selection ===")

do {
    // Exactly what usage.json looks like on an account without a 5-hour limit.
    let info = decode("""
    {"five_hour":{"used_percentage":null,"resets_at":null},
     "seven_day":{"used_percentage":48,"resets_at":\(now + 2 * day + 3 * hour + 120)},
     "model":"Opus","updated_at":\(now)}
    """)
    check("no 5-hour value falls back to 7-day", info.menuBarWindow(now: now)?.kind == .sevenDay)
    eq("7-day pct + time", info.menuBarText(showPercent: true, showResetTime: true, now: now), "48% 2d3h")
    eq("7-day pct only", info.menuBarText(showPercent: true, showResetTime: false, now: now), "48%")
    eq("7-day time only", info.menuBarText(showPercent: false, showResetTime: true, now: now), "2d3h")
    eq("both toggles off", info.menuBarText(showPercent: false, showResetTime: false, now: now), nil)
}

do {
    let info = decode("""
    {"seven_day":{"used_percentage":12.7,"resets_at":\(now + 5 * hour)}}
    """)
    check("missing five_hour key falls back to 7-day", info.menuBarWindow(now: now)?.kind == .sevenDay)
    eq("under one day shows h/m", info.menuBarText(showPercent: true, showResetTime: true, now: now), "12% 5h0m")
}

do {
    let info = decode("""
    {"five_hour":{"used_percentage":42,"resets_at":\(now + 3 * hour + 12 * 60)},
     "seven_day":{"used_percentage":48,"resets_at":\(now + 2 * day)}}
    """)
    check("live 5-hour window wins", info.menuBarWindow(now: now)?.kind == .fiveHour)
    eq("5-hour text unchanged (no prefix)", info.menuBarText(showPercent: true, showResetTime: true, now: now), "42% 3h12m")
}

do {
    let info = decode("""
    {"five_hour":{"used_percentage":90,"resets_at":\(now - 60)},
     "seven_day":{"used_percentage":48,"resets_at":\(now + day)}}
    """)
    check("elapsed 5-hour window falls back to 7-day", info.menuBarWindow(now: now)?.kind == .sevenDay)
    eq("elapsed 5-hour text", info.menuBarText(showPercent: true, showResetTime: true, now: now), "48% 1d0h")
}

do {
    let info = decode("""
    {"five_hour":{"used_percentage":30,"resets_at":null},
     "seven_day":{"used_percentage":48,"resets_at":\(now + day)}}
    """)
    check("5-hour value without reset time still wins", info.menuBarWindow(now: now)?.kind == .fiveHour)
    eq("5-hour time only with unknown reset", info.menuBarText(showPercent: false, showResetTime: true, now: now), nil)
}

do {
    let info = decode("""
    {"five_hour":{"used_percentage":70,"resets_at":\(now - 60)},
     "seven_day":{"used_percentage":null,"resets_at":null}}
    """)
    check("no 7-day value keeps last 5-hour value", info.menuBarWindow(now: now)?.kind == .fiveHour)
    eq("stale 5-hour pct", info.menuBarText(showPercent: true, showResetTime: true, now: now), "70%")
}

do {
    let info = decode("""
    {"five_hour":{"used_percentage":null,"resets_at":null},
     "seven_day":{"used_percentage":null,"resets_at":null}}
    """)
    check("nothing to show", info.menuBarWindow(now: now) == nil)
    eq("nothing to show text", info.menuBarText(showPercent: true, showResetTime: true, now: now), nil)
}

print("\n=== Dropdown reset string ===")

eq("days", RateLimitWindow(usedPercentage: 1, resetsAt: now + 2 * day + 3 * hour).resetTimeString(now: now), "2d 3h")
eq("hours", RateLimitWindow(usedPercentage: 1, resetsAt: now + 4 * hour + 12 * 60).resetTimeString(now: now), "4h 12m")
eq("minutes", RateLimitWindow(usedPercentage: 1, resetsAt: now + 8 * 60).resetTimeString(now: now), "8m")
eq("under a minute", RateLimitWindow(usedPercentage: 1, resetsAt: now + 20).resetTimeString(now: now), "<1m")
eq("elapsed", RateLimitWindow(usedPercentage: 1, resetsAt: now - 1).resetTimeString(now: now), nil)

print("\n========================================")
print("Usage results: \(passed) passed, \(failed) failed")
print("========================================")
exit(failed > 0 ? 1 : 0)
