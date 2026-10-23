import Foundation

/// The words of the blocked-app panel (design 10): during a session the
/// time left and the task; outside one, the rule and when it ends.
public struct BlockedAppText: Sendable {
    public var headline: String
    public var detail: String
    public var footer: String

    /// `session` is the active session, if any; it is shown whatever rule hid the app.
    public init(appName: String, reason: AppBlockReason, session: FocusSession?, at now: Date) {
        footer = "\(appName) was hidden, not quit. Nothing was closed. Exceptions cover the whole app."
        if let session {
            headline = "Focus session · \(SessionText(session).timeLeft(at: now)) left"
            detail = "You're working on \(session.action)"
            return
        }
        headline = "No session running"
        switch reason {
        case .always:
            detail = "Blocked at all times"
        case .session:
            detail = "Blocked during focus sessions"
        case .schedule(let schedule):
            var parts = ["Blocked by a schedule", RuleText.summary(schedule), schedule.timeZone.identifier]
            if let end = schedule.nextChange(after: now) {
                parts.append("ends \(Self.day(of: end, from: now, in: schedule.timeZone)) at \(Self.time(end, in: schedule.timeZone)) (in \(Self.duration(end.timeIntervalSince(now))))")
            }
            detail = parts.joined(separator: " · ")
        }
    }

    /// The exception button: plain, counting down a strict wait, then "Allow now".
    public static func exceptionButton(availableAt: Date?, now: Date) -> String {
        guard let availableAt else { return "Request a timed exception…" }
        return now >= availableAt ? "Allow now"
            : "Request a timed exception… available in " + MenuBarStatus.format(remaining: availableAt.timeIntervalSince(now))
    }

    /// The form's Allow button: plain, then counting down a confirmed strict wait.
    public static func allowButton(availableAt: Date?, now: Date) -> String {
        guard let availableAt else { return "Allow" }
        return now >= availableAt ? "Allow now" : "Allow in " + MenuBarStatus.format(remaining: availableAt.timeIntervalSince(now))
    }


    /// "3 h 17 min", "45 min".
    static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int((max(0, interval) / 60).rounded(.up))
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }

    private static func day(of instant: Date, from now: Date, in timeZone: TimeZone) -> String {
        Calendar.gregorian(in: timeZone).isDate(instant, inSameDayAs: now) ? "today" : formatted(instant, "EEE", timeZone)
    }

    private static func time(_ instant: Date, in timeZone: TimeZone) -> String {
        formatted(instant, "HH:mm", timeZone)
    }

    private static func formatted(_ instant: Date, _ pattern: String, _ timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: instant)
    }
}

/// The Apps line of protection status, kept apart from browsers (decision
/// 0003, 2026-10-14): app hiding works only while FocusPilot runs.
public struct AppProtectionText: Sendable {
    public var summary: String
    public var detail = "Only while FocusPilot is running"
    /// Apps are hidden right now; false when none is, or hiding isn't running.
    public var isProtected: Bool
    /// After "Apps ·" in the sidebar footer (design 01), with the prefix.
    public var short: String {
        if isProtected { "Apps · protected while running" } else if summary.hasPrefix("Apps not protected") {
            "Apps · not protected"
        } else { "Apps · none hidden now" }
    }

    /// `isRunning`: whether `AppBlocker` watches app launches right now (#17).
    public init(rules: [BlockRuleSet], policy: CompiledPolicy?, at now: Date, isRunning: Bool = true) {
        let apps = Self.apps(in: rules)
        let hidden = apps.filter { AppBlocking.verdict(for: $0.bundleID, policy: policy, at: now) != .allow }
        var unexcepted = policy
        unexcepted?.exceptions = []
        let excepted = apps.filter {
            !hidden.contains($0) && AppBlocking.verdict(for: $0.bundleID, policy: unexcepted, at: now) != .allow
        }
        isProtected = isRunning && !hidden.isEmpty
        summary = if !hidden.isEmpty && !isRunning {
            "Apps not protected · " + hidden.map(\.name).joined(separator: ", ")
        } else if !hidden.isEmpty {
            "Apps protected · " + hidden.map(\.name).joined(separator: ", ")
        } else if !excepted.isEmpty {
            "No apps hidden now · " + excepted.map(\.name).joined(separator: ", ") + (excepted.count == 1 ? " has an exception" : " have exceptions")
        } else if !apps.isEmpty {
            "No apps hidden now"
        } else {
            "No apps blocked"
        }
        if !isRunning && !hidden.isEmpty { detail = "App blocking isn't running" }
    }

    /// The pre-flight Apps row (design 11): apps a session starting now
    /// would hide: session-only and always rules, and schedules open now.
    public static func preflight(rules: [BlockRuleSet], at now: Date) -> String {
        let applying = rules.filter {
            switch $0.activation {
            case .always, .sessionOnly: true
            case .schedule(let schedule): schedule.contains(now)
            }
        }
        let apps = Self.apps(in: applying)
        return apps.isEmpty ? "No apps blocked" : apps.map(\.name).joined(separator: ", ") + " hidden on open · only while FocusPilot runs"
    }

    private struct App: Equatable {
        var bundleID: String
        var name: String
    }

    /// App targets in rule order, each bundle once.
    private static func apps(in rules: [BlockRuleSet]) -> [App] {
        var seen = Set<String>()
        return rules.flatMap(\.targets).compactMap {
            guard case .app(let bundleID, let name) = $0, seen.insert(bundleID.lowercased()).inserted else { return nil }
            return App(bundleID: bundleID, name: name)
        }
    }
}
