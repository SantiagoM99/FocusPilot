import Foundation
import GRDB

extension TaskRepository {
    public enum WrapUpError: Error, Equatable {
        /// The task was deleted while the wrap-up sheet was open.
        case taskNotFound
    }

    /// Appends the owner's wrap-up for `session` to the task's history and
    /// makes its return cue the next action, marking the task done if asked,
    /// all in one write. Every task that changes gets one new revision and
    /// update time.
    public func saveWrapUp(_ wrapUp: WrapUp, forTask id: Int64, session: UUID, markingDone: Bool = false) async throws {
        let savedAt = now()
        try await ownerDatabase.write { db in
            try db.execute(sql: "UPDATE task SET nextAction = ?, revision = revision + 1, updatedAt = ? WHERE id = ?",
                           arguments: [wrapUp.returnCue, savedAt, id])
            guard db.changesCount == 1 else { throw WrapUpError.taskNotFound }
            try WrapUpRecord(wrapUp, task: id, session: session, at: savedAt).insert(db)
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

    /// Every wrap-up saved on the task, newest first.
    public func wrapUpHistory(forTask id: Int64) async throws -> [TaskWrapUp] {
        try await ownerDatabase.read { db in
            try WrapUpRecord.filter(Column("taskId") == id).order(Column("id").desc).fetchAll(db).map(\.taskWrapUp)
        }
    }
}
