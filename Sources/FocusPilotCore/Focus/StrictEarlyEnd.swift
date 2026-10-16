import Foundation

/// Friction before a strict session ends ahead of its planned end, matching
/// the friction for exceptions: the owner confirms, then waits.
public enum StrictEarlyEnd {
    /// The 60-second wait the owner confirmed on PR #37 (decision 0003).
    /// Change it only here.
    public static let wait: TimeInterval = 60
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
