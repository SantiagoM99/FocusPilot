import Foundation

/// Session wrap-up (#20): what the owner records when a session ends, kept
/// as history on the task.
extension FocusCoordinator {
    /// Saves the wrap-up for an ended `session`, marking its task done if
    /// asked. Wrap-ups follow the end of a session only (owner decision,
    /// 2026-10-17), so one for the session still running or paused is refused.
    public func saveWrapUp(_ wrapUp: WrapUp, after ended: FocusSession, markingDone: Bool = false) async throws {
        if let current = session, current.id == ended.id, !current.hasEnded {
            throw SessionError.sessionStillActive
        }
        try await repository.saveWrapUp(wrapUp, forTask: ended.taskID, session: ended.id, markingDone: markingDone)
        await broadcast()
    }

    /// Every wrap-up saved on the task, newest first.
    public func wrapUpHistory(forTask id: Int64) async throws -> [TaskWrapUp] {
        try await repository.wrapUpHistory(forTask: id)
    }
}
