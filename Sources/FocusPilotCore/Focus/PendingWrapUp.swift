/// A wrap-up waiting for the owner, with what they have typed so far.
///
/// The app keeps this rather than the sheet, so closing and reopening the
/// planning window, or the same prompt arriving again, never loses text.
public struct PendingWrapUp: Equatable, Sendable, Identifiable {
    public var prompt: WrapUpPrompt
    public var draft: WrapUpDraft

    public var id: WrapUpPrompt.ID {
        prompt.id
    }

    /// The pending wrap-up after `prompt` arrives: the current one keeps its
    /// draft when it is for the same session; otherwise the draft starts
    /// from `task` (see `WrapUpDraft(task:)`).
    public static func receiving(_ prompt: WrapUpPrompt, replacing current: PendingWrapUp?, task: TodayItem?) -> PendingWrapUp {
        if let current, current.id == prompt.id {
            return PendingWrapUp(prompt: prompt, draft: current.draft)
        }
        return PendingWrapUp(prompt: prompt, draft: task.map(WrapUpDraft.init(task:)) ?? WrapUpDraft())
    }
}
