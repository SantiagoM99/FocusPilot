import Foundation

/// How blocking behaves when the app cannot update the policy (owner decision,
/// 2026-10-13, ARCHITECTURE.md "Enforcement ownership").
public enum SessionMode: String, Codable, Sendable {
    /// Extensions stop blocking at the planned end on their own.
    case normal = "normal"
    /// Extensions keep blocking past the planned end until the app confirms the end.
    case strict = "strict"
}

/// Why a session stopped.
public enum EndReason: String, Codable, Sendable {
    case completed = "completed"
    case reachedPlannedEnd = "reachedPlannedEnd"
}

/// Persisted with explicit keys; see `SessionPhase+Codable.swift`.
public enum SessionPhase: Equatable, Sendable {
    case running
    case paused(since: Date)
    case onBreak(until: Date)
    case ended(at: Date, reason: EndReason)
}

/// A focus session as the engine sees it and the coordinator persists it.
///
/// Every time is an absolute instant, so a session restored after a crash or
/// sleep is judged against the wall clock rather than a timer that stopped.
///
/// A session covers projects, not one task (#56, decision 0004): `taskID`
/// and `action` are the task in Now, which can change while the session
/// runs, and are nil while nothing is in Now.
public struct FocusSession: Codable, Equatable, Sendable {
    public var id: UUID
    public var taskID: Int64?
    public var action: String?
    public var mode: SessionMode
    public var startedAt: Date
    public var plannedEnd: Date
    public var phase: SessionPhase
    public var scope: SessionScope

    public init(
        id: UUID, taskID: Int64?, action: String?, mode: SessionMode,
        startedAt: Date, plannedEnd: Date, phase: SessionPhase, scope: SessionScope = .allProjects
    ) {
        self.id = id
        self.taskID = taskID
        self.action = action
        self.mode = mode
        self.startedAt = startedAt
        self.plannedEnd = plannedEnd
        self.phase = phase
        self.scope = scope
    }

    // Spelled out so renaming a property cannot silently change stored JSON.
    enum CodingKeys: String, CodingKey {
        case id, taskID, action, mode, startedAt, plannedEnd, phase, scope
    }

    /// Sessions saved before #56 have no scope and read as all projects.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decode(UUID.self, forKey: .id),
                  taskID: try container.decodeIfPresent(Int64.self, forKey: .taskID),
                  action: try container.decodeIfPresent(String.self, forKey: .action),
                  mode: try container.decode(SessionMode.self, forKey: .mode),
                  startedAt: try container.decode(Date.self, forKey: .startedAt),
                  plannedEnd: try container.decode(Date.self, forKey: .plannedEnd),
                  phase: try container.decode(SessionPhase.self, forKey: .phase),
                  scope: try container.decodeIfPresent(SessionScope.self, forKey: .scope) ?? .allProjects)
    }

    /// The task now in Now, or none.
    public mutating func follow(now task: (id: Int64, title: String)?) {
        taskID = task?.id
        action = task?.title
    }

    public var hasEnded: Bool {
        if case .ended = phase { true } else { false }
    }

    /// When the coordinator should next send `.reconcile`, or `nil` if nothing is pending.
    ///
    /// Exception expiries (#14) will join this as further deadlines.
    public var nextDeadline: Date? {
        switch phase {
        case .running, .paused: plannedEnd
        case .onBreak(let until): min(until, plannedEnd)
        case .ended: nil
        }
    }
}
