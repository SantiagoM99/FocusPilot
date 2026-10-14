import Foundation

/// How blocking behaves when the app cannot update the policy (owner decision,
/// 2026-10-13, ARCHITECTURE.md "Enforcement ownership").
public enum SessionMode: String, Codable, Sendable {
    /// Extensions stop blocking at the planned end on their own.
    case normal
    /// Extensions keep blocking past the planned end until the app confirms the end.
    case strict
}

/// Why a session stopped.
public enum EndReason: String, Codable, Sendable {
    case completed
    case reachedPlannedEnd
}

public enum SessionPhase: Codable, Equatable, Sendable {
    case running
    case paused(since: Date)
    case onBreak(until: Date)
    case ended(at: Date, reason: EndReason)
}

/// A focus session as the engine sees it and the coordinator persists it.
///
/// Every time is an absolute instant, so a session restored after a crash or
/// sleep is judged against the wall clock rather than a timer that stopped.
public struct FocusSession: Codable, Equatable, Sendable {
    public var id: UUID
    public var taskID: Int64
    public var action: String
    public var mode: SessionMode
    public var startedAt: Date
    public var plannedEnd: Date
    public var phase: SessionPhase

    public init(
        id: UUID, taskID: Int64, action: String, mode: SessionMode,
        startedAt: Date, plannedEnd: Date, phase: SessionPhase
    ) {
        self.id = id
        self.taskID = taskID
        self.action = action
        self.mode = mode
        self.startedAt = startedAt
        self.plannedEnd = plannedEnd
        self.phase = phase
    }

    public var hasEnded: Bool {
        if case .ended = phase { true } else { false }
    }
}
