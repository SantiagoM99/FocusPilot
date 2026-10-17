import Foundation

/// Friction during a strict session, matching the friction for exceptions:
/// the owner confirms, then waits. It applies to ending the session early
/// and to weakening a block rule (decision 0003, 2026-10-16 and 2026-10-17).
public enum StrictEarlyEnd {
    /// The 60-second wait the owner confirmed on PR #37 (decision 0003).
    /// Change it only here.
    public static let wait: TimeInterval = 60

    /// "1 minute", "90 seconds": the wait as the confirmations say it.
    public static var waitText: String {
        let seconds = Int(wait)
        return seconds % 60 == 0 ? "\(seconds / 60) minute\(seconds == 60 ? "" : "s")" : "\(seconds) seconds"
    }
}

/// A request the owner confirmed during a strict session, waiting
/// `StrictEarlyEnd.wait` from `confirmedAt` on the coordinator's monotonic
/// clock, so changing the Mac's clock cannot skip it.
struct StrictWait<Request: Equatable & Sendable>: Sendable {
    let request: Request
    let confirmedAt: Duration

    func remaining(at uptime: Duration) -> Duration {
        max(.zero, confirmedAt + .seconds(StrictEarlyEnd.wait) - uptime)
    }
}

/// What happened when the owner asked to complete the session.
public enum SessionCompletion: Equatable, Sendable {
    case completed
    /// A strict session ending early: the owner must confirm first; nothing
    /// changed.
    case needsConfirmation
    /// A strict session ending early: ask again at or after this instant.
    case waitUntil(Date)
}

/// A rule change the owner asked for.
public enum RuleEdit: Equatable, Sendable {
    case save(BlockRuleSet)
    case delete(Int64)
}

/// A weakening rule change waiting out its strict-session delay.
public struct PendingRuleEdit: Equatable, Sendable {
    public var edit: RuleEdit
    /// When asking again applies it.
    public var availableAt: Date
}

/// What happened when the owner asked to change a rule.
public enum RuleEditOutcome: Equatable, Sendable {
    case saved
    /// The change weakens blocking during a strict session: the owner must
    /// confirm first; nothing changed.
    case needsConfirmation
    /// Confirmed: ask again with the same change at or after this instant.
    case waitUntil(Date)
}
