import Foundation
import GRDB

/// One saved wrap-up: append-only history per task (owner decision,
/// 2026-10-17). The latest row, by insertion, is the task's return cue.
struct WrapUpRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "wrapUp"

    var id: Int64?
    var taskId: Int64
    var sessionId: String
    var savedAt: Date
    var outcome: String?
    var remainingWork: String?
    var returnCue: String?

    init(_ wrapUp: WrapUp, task: Int64, session: UUID, at savedAt: Date) {
        taskId = task
        sessionId = session.uuidString
        self.savedAt = savedAt
        outcome = wrapUp.outcome
        remainingWork = wrapUp.remainingWork
        returnCue = wrapUp.returnCue
    }

    var taskWrapUp: TaskWrapUp {
        TaskWrapUp(WrapUp(outcome: outcome, remainingWork: remainingWork, returnCue: returnCue),
                   session: UUID(uuidString: sessionId)!, at: savedAt)
    }

    /// The latest wrap-up of each of `tasks` that has one, by task id.
    static func latest(forTasks tasks: [Int64], _ db: Database) throws -> [Int64: TaskWrapUp] {
        let rows = try filter(sql: "id IN (SELECT MAX(id) FROM wrapUp GROUP BY taskId)")
            .filter(tasks.contains(Column("taskId")))
            .fetchAll(db)
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.taskId, $0.taskWrapUp) })
    }
}
