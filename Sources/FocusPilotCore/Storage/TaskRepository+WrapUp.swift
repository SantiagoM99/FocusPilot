import Foundation
import GRDB

extension TaskRepository {
    public enum WrapUpError: Error, Equatable {
        /// The task was deleted while the wrap-up sheet was open.
        case taskNotFound
    }

    /// Saves the owner's wrap-up on a task, and marks it done if asked, in
    /// one write. Every task that changes gets one new revision and update
    /// time. The return cue also becomes the next action.
    public func saveWrapUp(_ wrapUp: WrapUp, forTask id: Int64, markingDone: Bool = false) async throws {
        let savedAt = now()
        try await ownerDatabase.write { db in
            try db.execute(sql: """
                UPDATE task SET lastOutcome = ?, remainingWork = ?, returnCue = ?, nextAction = ?, wrappedUpAt = ?,
                    revision = revision + 1, updatedAt = ?
                WHERE id = ?
                """, arguments: [wrapUp.outcome, wrapUp.remainingWork, wrapUp.returnCue, wrapUp.returnCue,
                                 savedAt, savedAt, id])
            guard db.changesCount == 1 else { throw WrapUpError.taskNotFound }
            guard markingDone else { return }
            let positions = try Row.fetchAll(db, sql: "SELECT id, status, rank FROM task")
                .map { TaskPosition(id: $0["id"], status: TaskStatus(rawValue: $0["status"])!, rank: $0["rank"]) }
            for change in TaskOrder.complete(id, in: positions) {
                // The wrapped-up task already has its new revision above.
                let bump = change.id == id ? "" : ", revision = revision + 1, updatedAt = :updatedAt"
                try db.execute(sql: "UPDATE task SET status = :status, rank = :rank\(bump) WHERE id = :id",
                               arguments: ["status": change.status.rawValue, "rank": change.rank,
                                           "updatedAt": savedAt, "id": change.id])
            }
        }
    }
}
