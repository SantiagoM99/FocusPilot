import Foundation

/// The words Settings shows for rules: activation names, schedule
/// summaries and whether a rule blocks now. Times are 24-hour "HH:mm" in
/// the schedule's own time zone, as the policy stores them.
public enum RuleText {
    public static func activationName(_ activation: RuleActivation) -> String {
        switch activation {
        case .always: "Always"
        case .schedule: "Schedule"
        case .sessionOnly: "Session only"
        }
    }

    /// "Mon–Fri 08:00–18:00", "Sat, Sun 22:00–02:00", "Every day 08:00–18:00".
    public static func summary(_ schedule: WeeklySchedule) -> String {
        "\(days(schedule.days)) \(schedule.start)–\(schedule.end)"
    }

    /// A rule set's status. Rules with only apps say they hide them while
    /// the rule applies, or show an app exception's time left.
    public static func status(_ rule: BlockRuleSet, at now: Date, sessionRulesApply: Bool,
                              exceptions: [PolicyException] = []) -> String {
        let apps = rule.targets.compactMap { if case .app(let bundleID, _) = $0 { bundleID.lowercased() } else { nil } }
        guard !apps.isEmpty, apps.count == rule.targets.count else {
            return status(rule.activation, at: now, sessionRulesApply: sessionRulesApply)
        }
        if let expiry = exceptions.filter({ exception in apps.contains { exception.exempts(app: $0, at: now) } }).map(\.expiresAt).max() {
            return "Exception · \(BlockedAppText.duration(expiry.timeIntervalSince(now))) left"
        }
        let applies = switch rule.activation {
        case .always: true
        case .sessionOnly: sessionRulesApply
        case .schedule(let schedule): schedule.contains(now)
        }
        return applies ? "Hidden when opened" : status(rule.activation, at: now, sessionRulesApply: sessionRulesApply)
    }

    /// "Blocked now", "During focus sessions", "Ends 18:00", "Starts Mon 08:00".
    public static func status(_ activation: RuleActivation, at now: Date, sessionRulesApply: Bool) -> String {
        switch activation {
        case .always:
            return "Blocked now"
        case .sessionOnly:
            return sessionRulesApply ? "Blocked now" : "During focus sessions"
        case .schedule(let schedule):
            let verb = schedule.contains(now) ? "Ends" : "Starts"
            guard let change = schedule.nextChange(after: now) else { return verb }
            return "\(verb) \(when(change, from: now, in: schedule.timeZone))"
        }
    }

    /// "18:00" today, "Mon 08:00" on another day.
    private static func when(_ instant: Date, from now: Date, in timeZone: TimeZone) -> String {
        let calendar = Calendar.gregorian(in: timeZone)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateFormat = calendar.isDate(instant, inSameDayAs: now) ? "HH:mm" : "EEE HH:mm"
        return formatter.string(from: instant)
    }

    private static func days(_ days: Set<Weekday>) -> String {
        guard days.count < 7 else { return "Every day" }
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        var runs: [[Int]] = []
        for index in Weekday.allCases.indices where days.contains(Weekday.allCases[index]) {
            if let last = runs.last?.last, last == index - 1 { runs[runs.count - 1].append(index) } else { runs.append([index]) }
        }
        return runs.flatMap { run in
            run.count >= 3 ? ["\(names[run.first!])–\(names[run.last!])"] : run.map { names[$0] }
        }.joined(separator: ", ")
    }
}

/// What Settings says when an edit is refused.
public enum RuleErrorText {
    public static func message(_ error: RuleError) -> String {
        switch error {
        case .noTargets: "Add at least one site or app."
        case .invalidSchedule: "Pick at least one day, and make the start and end times different."
        case .invalidSite(let typed): "“\(typed)” isn't a site address."
        case .invalidApp: "That app has no bundle identifier."
        case .weakensStrictSession: "This weakens a rule during a strict session."
        case .notBlockable(let target): "\(target.displayName) is a command-line tool and can't be blocked."
        case .alreadyAllowed(let target): "\(target.displayName) is in Allowed. Remove it there first."
        case .alreadyBlocked(let target): "\(target.displayName) is blocked by a rule. Remove it there first."
        case .ruleChanged: "This rule changed since you opened it. Check it and try again."
        }
    }
}

extension RuleText {
    /// The question asked before a weakening change during a strict session.
    public static func title(_ edit: RuleEdit, rules: [BlockRuleSet]) -> String {
        switch edit {
        case .delete(let id):
            guard let rule = rules.first(where: { $0.id == id }) else { return "Remove this rule?" }
            return "Remove the rule for \(names(rule))?"
        case .save(let rule):
            return "Loosen the rule for \(names(rules.first { $0.id == rule.id } ?? rule))?"
        }
    }

    /// "You can apply it in 0:45", then "You can apply it now".
    public static func applyCountdown(availableAt: Date, now: Date) -> String {
        now >= availableAt ? "You can apply it now" : "You can apply it in " + MenuBarStatus.format(remaining: availableAt.timeIntervalSince(now))
    }

    /// Said under the editor's site field when the typed text names a page.
    public static func wholeDomainNote(_ typed: String) -> String? {
        guard SiteDomain.namesAPage(typed), let domain = SiteDomain.normalized(typed) else { return nil }
        return "Blocks all of \(domain), not only this page."
    }

    private static func names(_ rule: BlockRuleSet) -> String {
        rule.targets.map(\.displayName).joined(separator: ", ")
    }
}
