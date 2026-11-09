import Foundation

/// The words Settings shows for rules: activation labels, schedule
/// summaries and running exceptions. Summaries are 24-hour "HH:mm" in the
/// schedule's own time zone, as the policy stores them.
public enum RuleText {
    /// "Always", "During focus", "Weekdays 8:00 to 18:00".
    public static func activationLabel(_ activation: RuleActivation) -> String {
        switch activation {
        case .always: "Always"
        case .sessionOnly: "During focus"
        case .schedule(let schedule): "\(dayLabel(schedule.days)) \(clock(schedule.start)) to \(clock(schedule.end))"
        }
    }

    /// "Mon–Fri 08:00–18:00", "Sat, Sun 22:00–02:00", "Every day 08:00–18:00".
    public static func summary(_ schedule: WeeklySchedule) -> String {
        "\(days(schedule.days)) \(schedule.start)–\(schedule.end)"
    }

    /// A running exception on the rule's targets, as Settings shows it in
    /// place of the activation; nil when none is running.
    public static func exceptionStatus(_ rule: BlockRuleSet, at now: Date, exceptions: [PolicyException]) -> String? {
        if let excepted = siteExceptionStatus(rule, at: now, exceptions: exceptions) { return excepted }
        let apps = rule.targets.compactMap { if case .app(let bundleID, _) = $0 { bundleID.lowercased() } else { nil } }
        guard let expiry = exceptions.filter({ exception in apps.contains { exception.exempts(app: $0, at: now) } }).map(\.expiresAt).max() else {
            return nil
        }
        return "Exception · \(BlockedAppText.duration(expiry.timeIntervalSince(now))) left"
    }

    /// "Exception · whole site · 8 min left", "Exception · 2 pages · 12 min
    /// left" for running exceptions on the rule's sites; a site exception
    /// covers its pages, so it is the one shown.
    private static func siteExceptionStatus(_ rule: BlockRuleSet, at now: Date, exceptions: [PolicyException]) -> String? {
        let domains = rule.targets.compactMap { if case .site(let domain) = $0 { domain } else { nil } }
        let running = exceptions.filter { exception in
            now < exception.expiresAt && exception.scope.siteHost.map { host in domains.contains { SiteDomain.domain(host, isWithin: $0) } } == true
        }
        let sites = running.filter { if case .site = $0.scope { true } else { false } }
        let shown = sites.isEmpty ? running : sites
        guard let expiry = shown.map(\.expiresAt).max() else { return nil }
        let what = !sites.isEmpty ? "whole site" : shown.count == 1 ? "1 page" : "\(shown.count) pages"
        return "Exception · \(what) · \(BlockedAppText.duration(expiry.timeIntervalSince(now))) left"
    }

    /// "Weekdays", "Weekends", or the days by name.
    private static func dayLabel(_ days: Set<Weekday>) -> String {
        if days == [.mon, .tue, .wed, .thu, .fri] { return "Weekdays" }
        if days == [.sat, .sun] { return "Weekends" }
        return Self.days(days)
    }

    /// "8:00", "18:30".
    private static func clock(_ time: ClockTime) -> String {
        String(format: "%d:%02d", time.hour, time.minute)
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

/// Running site and page exceptions as the menu bar lists them, soonest
/// expiry first: "Exception · 1 page on youtube.com · 8 min left".
public enum SiteExceptionText {
    public static func lines(_ exceptions: [PolicyException], at now: Date) -> [String] {
        exceptions.filter { now < $0.expiresAt }.sorted { $0.expiresAt < $1.expiresAt }.compactMap { exception in
            let left = BlockedAppText.duration(exception.expiresAt.timeIntervalSince(now))
            switch exception.scope {
            case .app: return nil
            case .site(let domain): return "Exception · all of \(domain) · \(left) left"
            case .page(let url): return "Exception · 1 page on \(PageAddress.host(url) ?? url) · \(left) left"
            }
        }
    }
}

/// The notification for an exception granted from Chrome's blocked page,
/// so a grant the owner did not ask for does not go unnoticed.
public struct ExceptionNoticeText: Equatable, Sendable {
    public var title: String
    public var body: String

    public static func grantedFromChrome(_ scope: ExceptionScope, until: Date, in timeZone: TimeZone = .current) -> ExceptionNoticeText {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        let what = switch scope {
        case .app(let bundleID): bundleID
        case .site(let domain): "All of \(domain)"
        case .page(let url): "1 page on \(PageAddress.host(url) ?? url)"
        }
        return ExceptionNoticeText(title: "Exception allowed from Chrome", body: "\(what) until \(formatter.string(from: until))")
    }
}
