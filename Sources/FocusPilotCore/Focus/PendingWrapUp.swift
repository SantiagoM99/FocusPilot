/// A wrap-up waiting for the owner, with what they have typed so far.
///
/// The app keeps this rather than the sheet, so closing and reopening the
/// planning window, or the same prompt arriving again, never loses text.
public struct PendingWrapUp: Equatable, Sendable, Identifiable {
    public var prompt: WrapUpPrompt
    public var draft: WrapUpDraft
    /// The session's other open tasks, in the order first touched (#57),
    /// each with one optional line in `draft.otherCues`.
    public var others: [TodayItem] = []

    /// False when the session ended with nothing in Now and touched no other task.
    public var isNeeded: Bool {
        prompt.session.taskID != nil || !others.isEmpty
    }

    public var id: WrapUpPrompt.ID {
        prompt.id
    }

    /// The pending wrap-up after `prompt` arrives: the current one keeps its
    /// draft when it is for the same session; otherwise the draft starts
    /// from `task` (see `WrapUpDraft(task:)`).
    public static func receiving(_ prompt: WrapUpPrompt, replacing current: PendingWrapUp?, task: TodayItem?,
                                 others: [TodayItem] = []) -> PendingWrapUp {
        if let current, current.id == prompt.id {
            return PendingWrapUp(prompt: prompt, draft: current.draft, others: others)
        }
        return PendingWrapUp(prompt: prompt, draft: task.map(WrapUpDraft.init(task:)) ?? WrapUpDraft(), others: others)
    }
}
