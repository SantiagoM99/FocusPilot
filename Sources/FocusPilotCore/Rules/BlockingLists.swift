import Foundation

/// One line in Settings › Blocking: a site, app or tool and its activation or kind.
public struct BlockingRow: Equatable, Identifiable, Sendable {
    public enum Source: Equatable, Sendable {
        case rule(BlockRuleSet)
        case allowed(Int64)
    }

    public var target: ActivityTarget
    public var title: String
    public var detail: String
    public var source: Source

    public var id: String {
        switch source {
        case .rule(let rule): "rule-\(rule.id ?? -1)-\(target)"
        case .allowed(let id): "allowed-\(id)"
        }
    }
}

/// The lists Settings › Blocking shows. A rule set can hold several sites and
/// apps; each gets its own row, in the list for its kind.
public struct BlockingLists: Equatable, Sendable {
    public var sites: [BlockingRow]
    public var apps: [BlockingRow]
    public var allowed: [BlockingRow]

    public init(rules: [BlockRuleSet], allowed: [AllowedActivity], at now: Date, exceptions: [PolicyException] = []) {
        let rows = rules.flatMap { rule in
            rule.targets.map { target in
                let alone = BlockRuleSet(id: rule.id, targets: [target], activation: rule.activation)
                return BlockingRow(target: target, title: target.displayName,
                                   detail: RuleText.exceptionStatus(alone, at: now, exceptions: exceptions) ?? RuleText.activationLabel(rule.activation),
                                   source: .rule(rule))
            }
        }
        sites = rows.filter { if case .site = $0.target { true } else { false } }
        apps = rows.filter { if case .app = $0.target { true } else { false } }
        self.allowed = allowed.compactMap { entry in
            entry.id.map { BlockingRow(target: entry.target, title: Self.title(entry), detail: Self.kind(entry.target), source: .allowed($0)) }
        }
    }

    private static func title(_ entry: AllowedActivity) -> String {
        if case .site(let domain) = entry.target { domain } else { entry.name }
    }

    private static func kind(_ target: ActivityTarget) -> String {
        switch target {
        case .site: "Site"
        case .app: "App"
        case .tool: "Tool"
        }
    }
}
