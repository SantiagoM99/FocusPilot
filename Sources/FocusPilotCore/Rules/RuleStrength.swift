import Foundation

/// Whether an edit makes a rule block less (owner decision, 0003,
/// 2026-10-17): removing a target, or blocking at fewer times. When in
/// doubt it counts as weakening, so a strict session waits rather than
/// loosening at once.
enum RuleStrength {
    static func weakens(_ old: BlockRuleSet, to new: BlockRuleSet) -> Bool {
        let kept = Set(new.targets.map(\.key))
        return !old.targets.allSatisfy { kept.contains($0.key) } || !covers(new.activation, old.activation)
    }

    /// Whether `wider` blocks at least whenever `narrower` does.
    private static func covers(_ wider: RuleActivation, _ narrower: RuleActivation) -> Bool {
        switch (wider, narrower) {
        case (.always, _), (.sessionOnly, .sessionOnly): true
        case (.schedule(let a), .schedule(let b)): covers(a, b)
        default: false
        }
    }

    private static func covers(_ wider: WeeklySchedule, _ narrower: WeeklySchedule) -> Bool {
        guard wider.timeZone == narrower.timeZone, wider.days.isSuperset(of: narrower.days) else { return false }
        if wider.crossesMidnight || narrower.crossesMidnight {
            return wider.start == narrower.start && wider.end == narrower.end
        }
        return wider.start <= narrower.start && wider.end >= narrower.end
    }
}
