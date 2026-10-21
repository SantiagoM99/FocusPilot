import Foundation

/// The wrap-up sheet's three fields and its "Mark task complete" box while
/// the owner edits them.
///
/// It starts from what the task already says (the remaining work from the
/// last wrap-up and the current next action), so an owner with nothing new
/// to add can save in one keystroke. Only the outcome starts empty.
public struct WrapUpDraft: Equatable, Sendable {
    public var outcome = ""
    public var remainingWork = ""
    public var returnCue = ""
    /// Always starts unticked: completing a task is the owner's explicit choice.
    public var marksTaskDone = false

    public init(outcome: String = "", remainingWork: String = "", returnCue: String = "", marksTaskDone: Bool = false) {
        self.outcome = outcome
        self.remainingWork = remainingWork
        self.returnCue = returnCue
        self.marksTaskDone = marksTaskDone
    }

    public init(task: TodayItem) {
        self.init(remainingWork: task.wrapUp?.remainingWork ?? "", returnCue: task.nextAction ?? "")
    }

    /// What is saved: trimmed text, with blank fields stored as nothing.
    public var wrapUp: WrapUp {
        WrapUp(outcome: Self.saved(outcome), remainingWork: Self.saved(remainingWork), returnCue: Self.saved(returnCue))
    }

    private static func saved(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
