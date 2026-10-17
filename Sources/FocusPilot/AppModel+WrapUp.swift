import Foundation
import FocusPilotCore

/// Session wrap-up (#20) as the views use it.
///
/// A prompt appears when the watched session pauses or ends and waits in
/// `wrapUp` until saved or skipped; the planning window shows it as a sheet.
/// Only the owner's own Pause or Complete brings that window forward: a
/// session reaching its planned end must not steal focus, so its wrap-up
/// waits for the owner to open FocusPilot.
extension AppModel {
    /// Called with every newer snapshot, before it replaces the shown one.
    func noticeWrapUp(from previous: FocusSession?, to current: FocusSession?) {
        guard let prompt = WrapUpPrompt.after(previous, current) else { return }
        wrapUp = prompt
        // A few seconds covers the snapshot arriving after the command; a
        // command that failed must not make a later automatic end steal focus.
        if let asked = ownerEndedOrPausedAt, Date.now.timeIntervalSince(asked) < 5 {
            ownerEndedOrPausedAt = nil
            planningWindowRequests += 1
        }
    }

    /// The fields as they start for this prompt's task.
    func draft(for prompt: WrapUpPrompt) -> WrapUpDraft {
        task(prompt.session.taskID).map(WrapUpDraft.init(task:)) ?? WrapUpDraft()
    }

    /// An open task by id, from Today.
    func task(_ id: Int64) -> TodayItem? {
        today.first { $0.id == id }
    }

    /// Saves and closes the sheet. Returns why nothing was saved, or nil;
    /// on failure the sheet stays open with the owner's text.
    func saveWrapUp(_ draft: WrapUpDraft, for prompt: WrapUpPrompt, markingDone: Bool) async -> String? {
        guard let coordinator else { return startupError }
        do {
            try await coordinator.saveWrapUp(draft.wrapUp, forTask: prompt.session.taskID, markingDone: markingDone)
        } catch {
            return "Could not save the wrap-up: \(error.localizedDescription)"
        }
        if wrapUp == prompt { wrapUp = nil }
        await refresh()
        return nil
    }

    func skipWrapUp() {
        wrapUp = nil
    }
}
