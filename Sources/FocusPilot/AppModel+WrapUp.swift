import Foundation
import FocusPilotCore

/// Session wrap-up (#20) as the views use it.
///
/// A prompt appears when the watched session ends (never on pause, owner
/// decision 2026-10-17) and waits in `wrapUp`, with the owner's typing,
/// until saved or skipped; the planning window shows it as a sheet. Only
/// the owner's own Complete brings that window forward: a session reaching
/// its planned end must not steal focus, so its wrap-up waits for the owner
/// to open FocusPilot.
extension AppModel {
    /// Called with every newer snapshot, before it replaces the shown one.
    func noticeWrapUp(from previous: FocusSession?, to current: FocusSession?) {
        guard let prompt = WrapUpPrompt.after(previous, current) else { return }
        wrapUp = PendingWrapUp.receiving(prompt, replacing: wrapUp, task: task(prompt.session.taskID))
        // A few seconds covers the snapshot arriving after the command; a
        // command that failed must not make a later automatic end steal focus.
        if let asked = ownerCompletedAt, Date.now.timeIntervalSince(asked) < 5 {
            ownerCompletedAt = nil
            planningWindowRequests += 1
        }
    }

    /// An open task by id, from Today.
    func task(_ id: Int64) -> TodayItem? {
        today.first { $0.id == id }
    }

    /// Saves the pending wrap-up and closes the sheet. Returns why nothing
    /// was saved, or nil; on failure the sheet stays open with the text.
    func saveWrapUp(markingDone: Bool) async -> String? {
        guard let pending = wrapUp else { return nil }
        guard let coordinator else { return startupError }
        do {
            try await coordinator.saveWrapUp(pending.draft.wrapUp, after: pending.prompt.session, markingDone: markingDone)
        } catch FocusCoordinator.SessionError.sessionStillActive where markingDone {
            return "A session on this task is still running. Save without marking it complete, or end that session first."
        } catch {
            return "Could not save the wrap-up: \(error.localizedDescription)"
        }
        if wrapUp?.id == pending.id { wrapUp = nil }
        await refresh()
        return nil
    }

    func skipWrapUp() {
        wrapUp = nil
    }
}
