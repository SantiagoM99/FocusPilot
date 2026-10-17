import Foundation

/// The wrap-up sheet's three fields while the owner edits them.
///
/// It starts from what the task already says (the remaining work from the
/// last wrap-up and the current next action), so an owner with nothing new
/// to add can save in one keystroke. Only the outcome starts empty.
public struct WrapUpDraft: Equatable, Sendable {
    public var outcome = ""
    public var remainingWork = ""
    public var returnCue = ""

    public init(outcome: String = "", remainingWork: String = "", returnCue: String = "") {
        self.outcome = outcome
        self.remainingWork = remainingWork
        self.returnCue = returnCue
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
