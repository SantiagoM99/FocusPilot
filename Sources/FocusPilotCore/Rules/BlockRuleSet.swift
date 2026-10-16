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
    /// Command-line tools can only be allowed; nothing can hide them.
    case notBlockable(ActivityTarget)
    case alreadyAllowed(ActivityTarget)
    case alreadyBlocked(ActivityTarget)
}

/// Keeps the blocked and allowed lists from contradicting each other: the
/// same site or app cannot be in both.
public enum ActivityLists {
    public static func conflict(blocking targets: [ActivityTarget], allowed: [AllowedActivity]) -> ActivityTarget? {
        let allowedKeys = Set(allowed.map(\.target.key))
        return targets.first { allowedKeys.contains($0.key) }
    }

    public static func conflict(allowing target: ActivityTarget, rules: [BlockRuleSet]) -> ActivityTarget? {
        rules.flatMap(\.targets).first { $0.key == target.key }
    }

    /// Checks a rule set before it is saved against the current allowed list.
    static func validate(_ rule: BlockRuleSet, allowed: [AllowedActivity]) throws {
        guard !rule.targets.isEmpty else { throw RuleError.noTargets }
        if case .schedule(let schedule) = rule.activation, !schedule.isValid { throw RuleError.invalidSchedule }
        if let tool = rule.targets.first(where: { if case .tool = $0 { true } else { false } }) {
            throw RuleError.notBlockable(tool)
        }
        if let conflict = conflict(blocking: rule.targets, allowed: allowed) { throw RuleError.alreadyAllowed(conflict) }
    }

    static func validate(_ entry: AllowedActivity, allowed: [AllowedActivity], rules: [BlockRuleSet]) throws {
        if let existing = allowed.first(where: { $0.target.key == entry.target.key }) { throw RuleError.alreadyAllowed(existing.target) }
        if let conflict = conflict(allowing: entry.target, rules: rules) { throw RuleError.alreadyBlocked(conflict) }
    }
}
