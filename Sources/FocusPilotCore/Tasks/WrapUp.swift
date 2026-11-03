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

/// A wrap-up saved on a task: what was written, after which session (none
/// for a return cue saved on Switch outside a session), and when.
public struct TaskWrapUp: Equatable, Sendable {
    public var outcome: String?
    public var remainingWork: String?
    public var returnCue: String?
    public var sessionID: UUID?
    public var savedAt: Date
    /// A "Where did you leave off?" note saved on Switch (#57), not a session wrap-up.
    public var isFromSwitch: Bool

    /// How the return cue is labeled where it is shown first.
    public var cueTitle: String {
        isFromSwitch ? "Where you left off" : "Start with"
    }

    /// The caption over a next action that is this return cue.
    public var nextActionCaption: String {
        isFromSwitch ? "Next action · where you left off" : "Next action · return cue from last session"
    }

    public init(_ wrapUp: WrapUp, session sessionID: UUID?, at savedAt: Date, isFromSwitch: Bool = false) {
        self.isFromSwitch = isFromSwitch
        outcome = wrapUp.outcome
        remainingWork = wrapUp.remainingWork
        returnCue = wrapUp.returnCue
        self.sessionID = sessionID
        self.savedAt = savedAt
    }
}
