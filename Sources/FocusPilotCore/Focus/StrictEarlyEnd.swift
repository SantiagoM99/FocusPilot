import Foundation

/// Friction before a strict session ends ahead of its planned end, matching
/// the friction for exceptions: the owner confirms, then waits.
public enum StrictEarlyEnd {
    /// PENDING OWNER SIGN-OFF: the proposed 60-second wait (decision 0003,
    /// 2026-10-14). Change it only here.
    public static let wait: TimeInterval = 60
}

/// What happened when the owner asked to complete the session.
public enum SessionCompletion: Equatable, Sendable {
    case completed
    /// A strict session ending early: ask again at or after this instant.
    case waitUntil(Date)
}
