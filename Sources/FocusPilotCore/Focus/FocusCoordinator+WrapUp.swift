import Foundation

/// Session wrap-up (#20): what the owner records when a session pauses or
/// ends, saved as task state.
extension FocusCoordinator {
    /// Saves the wrap-up on `taskID`, marking the task done if asked. A task
    /// whose session is still active cannot be marked done; end it first.
    public func saveWrapUp(_ wrapUp: WrapUp, forTask taskID: Int64, markingDone: Bool = false) async throws {
        if markingDone, let active = session, !active.hasEnded, active.taskID == taskID {
            throw SessionError.sessionStillActive
        }
        try await repository.saveWrapUp(wrapUp, forTask: taskID, markingDone: markingDone)
        await broadcast()
    }
}
