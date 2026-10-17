import Foundation

/// What the owner writes when a session ends: a brief outcome,
/// the work that remains and the return cue ("Next time, start with"),
/// which also becomes the task's next action.
public struct WrapUp: Equatable, Sendable {
    public var outcome: String?
    public var remainingWork: String?
    public var returnCue: String?

    public init(outcome: String? = nil, remainingWork: String? = nil, returnCue: String? = nil) {
        self.outcome = outcome
        self.remainingWork = remainingWork
        self.returnCue = returnCue
    }
}

/// A wrap-up saved on a task: what was written, after which session, and when.
public struct TaskWrapUp: Equatable, Sendable {
    public var outcome: String?
    public var remainingWork: String?
    public var returnCue: String?
    public var sessionID: UUID
    public var savedAt: Date

    public init(_ wrapUp: WrapUp, session sessionID: UUID, at savedAt: Date) {
        outcome = wrapUp.outcome
        remainingWork = wrapUp.remainingWork
        returnCue = wrapUp.returnCue
        self.sessionID = sessionID
        self.savedAt = savedAt
    }
}
