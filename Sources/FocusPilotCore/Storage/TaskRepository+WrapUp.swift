import Foundation
import GRDB

extension TaskRepository {
    public enum WrapUpError: Error, Equatable {
        /// The task was deleted while the wrap-up sheet was open.
        case taskNotFound
    }

    /// Saves the owner's wrap-up on a task in one write, bumping its
    /// revision and update time. The return cue also becomes the next action.
    public func saveWrapUp(_ wrapUp: WrapUp, forTask id: Int64) async throws {
        let savedAt = now()
        try await ownerDatabase.write { db in
            try db.execute(sql: """
                UPDATE task SET lastOutcome = ?, remainingWork = ?, returnCue = ?, nextAction = ?, wrappedUpAt = ?,
                    revision = revision + 1, updatedAt = ?
                WHERE id = ?
                """, arguments: [wrapUp.outcome, wrapUp.remainingWork, wrapUp.returnCue, wrapUp.returnCue,
                                 savedAt, savedAt, id])
            guard db.changesCount == 1 else { throw WrapUpError.taskNotFound }
        }
    }
}
