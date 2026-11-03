import Foundation

/// Session wrap-up (#20): what the owner records when a session ends, kept
/// as history on the task.
extension FocusCoordinator {
    /// Saves the wrap-up for an ended `session`, marking its task done if
    /// asked. Wrap-ups follow the end of a session only (owner decision,
    /// 2026-10-17), so one for the session still running or paused is refused,
    /// as is marking the task done while a later session on it is active.
    /// `others` holds the line written for each other task the session
    /// touched (#57), saved as its return cue; blank lines save nothing.
    /// With nothing in Now at the end only `others` are saved.
    public func saveWrapUp(_ wrapUp: WrapUp, after ended: FocusSession, markingDone: Bool = false,
                           others: [Int64: String] = [:]) async throws {
        if let current = session, !current.hasEnded,
           current.id == ended.id || (markingDone && current.taskID != nil && current.taskID == ended.taskID) {
            throw SessionError.sessionStillActive
        }
        let otherCues = others.compactMapValues { line -> WrapUp? in
            let cue = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return cue.isEmpty ? nil : WrapUp(returnCue: cue)
        }
        try await repository.saveWrapUp(wrapUp, forTask: ended.taskID, session: ended.id,
                                        markingDone: markingDone && ended.taskID != nil, others: otherCues)
        await followNowAfterTaskChange()
        await broadcast()
    }

    /// Every wrap-up saved on the task, newest first.
    public func wrapUpHistory(forTask id: Int64) async throws -> [TaskWrapUp] {
        try await repository.wrapUpHistory(forTask: id)
    }
}
