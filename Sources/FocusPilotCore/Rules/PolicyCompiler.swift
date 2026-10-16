import CryptoKit
import Foundation

/// Compiles rule sets, the allowed list and the session's policy into the
/// rules extensions enforce. Pure: the same inputs in any order give the
/// same rules and checksum.
public enum PolicyCompiler {
    public static func compile(rules: [BlockRuleSet], allowed: [AllowedActivity], session: SessionPolicy?) -> PolicyRules {
        var always: [ActivityTarget] = [], sessionOnly: [ActivityTarget] = []
        var scheduled: [WeeklySchedule: [ActivityTarget]] = [:]
        for rule in rules {
            switch rule.activation {
            case .always: always += rule.targets
            case .sessionOnly: sessionOnly += rule.targets
            case .schedule(let schedule): scheduled[schedule, default: []] += rule.targets
            }
        }
        let blocks = scheduled.map { ScheduledBlock(schedule: $0.key, targets: PolicyTargets($0.value)) }
            .sorted { sortKey($0) < sortKey($1) }
        let allowedTargets = PolicyTargets(allowed.map(\.target))
        let tools = Set(allowed.compactMap { if case .tool(let command) = $0.target { command } else { nil } })
        let content = Content(
            always: PolicyTargets(always),
            scheduled: blocks,
            session: session.map { SessionBlock($0, targets: PolicyTargets(sessionOnly)) },
            allowed: AllowedTargets(domains: allowedTargets.domains, apps: allowedTargets.apps, tools: tools.sorted())
        )
        return PolicyRules(always: content.always, scheduled: content.scheduled, session: content.session,
                           allowed: content.allowed, checksum: checksum(content))
    }

    private struct Content: Encodable {
        var always: PolicyTargets
        var scheduled: [ScheduledBlock]
        var session: SessionBlock?
        var allowed: AllowedTargets
    }

    private static func checksum(_ content: Content) -> String {
        let data = (try? CompiledPolicy.encoder().encode(content)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Orders schedule blocks by their encoded schedule, which is stable.
    private static func sortKey(_ block: ScheduledBlock) -> String {
        (try? CompiledPolicy.encoder().encode(block.schedule)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}
