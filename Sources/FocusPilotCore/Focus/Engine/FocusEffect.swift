import Foundation

/// The session's part of the policy that browser extensions enforce.
///
/// Only a running session has one. The compiled policy (always-on and
/// scheduled rule sets, exceptions) wraps this later; it is not built here.
public struct SessionPolicy: Equatable, Sendable {
    public var sessionID: UUID
    public var mode: SessionMode
    /// Absolute, so an extension can stop on time (normal) or keep going (strict) without the app.
    public var end: Date

    public init(sessionID: UUID, mode: SessionMode, end: Date) {
        self.sessionID = sessionID
        self.mode = mode
        self.end = end
    }
}

/// Something the owner should be told.
public enum FocusNotice: Equatable, Sendable {
    case sessionReachedPlannedEnd
    case breakEnded
}

/// Work the engine asks the coordinator to perform, in order.
public enum FocusEffect: Equatable, Sendable {
    case persist(FocusSession)
    /// `nil` means no session rules apply.
    case publishPolicy(SessionPolicy?)
    case notify(FocusNotice)
}

/// The engine's answer: the session after the event and the effects to perform.
public struct FocusTransition: Equatable, Sendable {
    public var session: FocusSession?
    public var effects: [FocusEffect]
}
