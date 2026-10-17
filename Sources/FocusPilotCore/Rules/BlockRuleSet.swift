import Foundation

/// When a rule set blocks (decision 0003, 2026-10-13).
public enum RuleActivation: Hashable, Codable, Sendable {
    /// Always blocked, with or without the app running.
    case always
    /// Blocked inside the schedule's windows, with or without the app.
    case schedule(WeeklySchedule)
    /// Blocked while session rules apply: a running session, or a paused or
    /// on-break strict one. Without the app, a normal session's rules end at
    /// its planned end and a strict one's continue.
    case sessionOnly
}

/// Owner-authored sites and apps blocked together under one activation.
public struct BlockRuleSet: Hashable, Sendable {
    /// `nil` until saved.
    public var id: Int64?
    public var targets: [ActivityTarget]
    public var activation: RuleActivation
    /// Grows with every saved edit.
    public var revision: Int

    public init(id: Int64? = nil, targets: [ActivityTarget], activation: RuleActivation, revision: Int = 1) {
        self.id = id
        self.targets = targets
        self.activation = activation
        self.revision = revision
    }
}

/// An app, site or tool that never triggers a check-in (design 07,
/// Allowed). The seeded tools can be removed like any other entry.
public struct AllowedActivity: Hashable, Sendable {
    public enum Source: String, Codable, Sendable {
        case seeded, owner
    }

    public var id: Int64?
    public var name: String
    public var target: ActivityTarget
    public var source: Source

    public init(id: Int64? = nil, name: String, target: ActivityTarget, source: Source = .owner) {
        self.id = id
        self.name = name
        self.target = target
        self.source = source
    }
}

/// Why a rule or allowed entry was refused.
public enum RuleError: Error, Equatable {
    case noTargets
    case invalidSchedule
    /// Text that is not a site address.
    case invalidSite(String)
    /// An app without a bundle ID, or a tool without a command.
    case invalidApp
    /// The edit weakens blocking during a strict session; the coordinator
    /// applies it only after the owner confirms and waits.
    case weakensStrictSession
    /// Command-line tools can only be allowed; nothing can hide them.
    case notBlockable(ActivityTarget)
    case alreadyAllowed(ActivityTarget)
    case alreadyBlocked(ActivityTarget)
}

/// Keeps the blocked and allowed lists from contradicting each other: the
/// same app, or overlapping sites (overleaf.com and cdn.overleaf.com),
/// cannot be in both. Conflicts name the entry already in the other list.
public enum ActivityLists {
    public static func conflict(blocking targets: [ActivityTarget], allowed: [AllowedActivity]) -> ActivityTarget? {
        allowed.map(\.target).first { existing in targets.contains { $0.overlaps(existing) } }
    }

    public static func conflict(allowing target: ActivityTarget, rules: [BlockRuleSet]) -> ActivityTarget? {
        rules.flatMap(\.targets).first { $0.overlaps(target) }
    }

    /// The target as stored: sites normalized to their domain. Throws for
    /// targets that cannot be stored. Every caller goes through this, not
    /// only the Settings editor.
    static func normalized(_ target: ActivityTarget) throws -> ActivityTarget {
        switch target {
        case .site(let typed):
            guard let domain = SiteDomain.normalized(typed) else { throw RuleError.invalidSite(typed) }
            return .site(domain: domain)
        case .app(let bundleID, let name):
            let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { throw RuleError.invalidApp }
            let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return .app(bundleID: id, name: title.isEmpty ? id : title)
        case .tool(let command):
            let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw RuleError.invalidApp }
            return .tool(command: trimmed)
        }
    }

    /// The rule with normalized targets, duplicates removed in order.
    static func normalized(_ rule: BlockRuleSet) throws -> BlockRuleSet {
        var result = rule
        var seen = Set<String>()
        result.targets = try rule.targets.map { try Self.normalized($0) }.filter { seen.insert($0.key).inserted }
        return result
    }

    static func normalized(_ entry: AllowedActivity) throws -> AllowedActivity {
        var result = entry
        result.target = try Self.normalized(entry.target)
        let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        result.name = name.isEmpty ? result.target.displayName : name
        return result
    }

    /// Checks a normalized rule set before it is saved against the current allowed list.
    static func validate(_ rule: BlockRuleSet, allowed: [AllowedActivity]) throws {
        guard !rule.targets.isEmpty else { throw RuleError.noTargets }
        if case .schedule(let schedule) = rule.activation, !schedule.isValid { throw RuleError.invalidSchedule }
        if let tool = rule.targets.first(where: { if case .tool = $0 { true } else { false } }) {
            throw RuleError.notBlockable(tool)
        }
        if let conflict = conflict(blocking: rule.targets, allowed: allowed) { throw RuleError.alreadyAllowed(conflict) }
    }

    static func validate(_ entry: AllowedActivity, allowed: [AllowedActivity], rules: [BlockRuleSet]) throws {
        if let existing = allowed.first(where: { $0.target.overlaps(entry.target) }) { throw RuleError.alreadyAllowed(existing.target) }
        if let conflict = conflict(allowing: entry.target, rules: rules) { throw RuleError.alreadyBlocked(conflict) }
    }
}
