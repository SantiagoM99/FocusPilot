import Foundation
import GRDB

/// One saved wrap-up: append-only history per task (owner decision,
/// 2026-10-17). The latest row, by insertion, is the task's return cue.
struct WrapUpRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "wrapUp"

    var id: Int64?
    var taskId: Int64
    /// Nil for a return cue saved on Switch outside a session (#57).
    var sessionId: String?
    var savedAt: Date
    var outcome: String?
    var remainingWork: String?
    var returnCue: String?
    /// "session" for a session wrap-up, "switch" for a note saved on Switch (#57).
    var kind: String

    init(_ wrapUp: WrapUp, task: Int64, session: UUID?, at savedAt: Date, fromSwitch: Bool = false) {
        kind = fromSwitch ? "switch" : "session"
        taskId = task
        sessionId = session?.uuidString
        self.savedAt = savedAt
        outcome = wrapUp.outcome
        remainingWork = wrapUp.remainingWork
        returnCue = wrapUp.returnCue
    }

    var taskWrapUp: TaskWrapUp {
        TaskWrapUp(WrapUp(outcome: outcome, remainingWork: remainingWork, returnCue: returnCue),
                   session: sessionId.flatMap(UUID.init(uuidString:)), at: savedAt, isFromSwitch: kind == "switch")
    }

    /// The latest wrap-up of each of `tasks` that has one, by task id. A
    /// Switch note (#57) replaces only the return cue: what got done and what
    /// remains come from the latest session wrap-up, so a quick note never
    /// hides them. A later session wrap-up stands on its own.
    static func latest(forTasks tasks: [Int64], _ db: Database) throws -> [Int64: TaskWrapUp] {
        let latest = try filter(sql: "id IN (SELECT MAX(id) FROM wrapUp GROUP BY taskId)")
            .filter(tasks.contains(Column("taskId")))
            .fetchAll(db)
        let sessions = try filter(sql: "id IN (SELECT MAX(id) FROM wrapUp WHERE kind = 'session' GROUP BY taskId)")
            .filter(latest.filter { $0.kind == "switch" }.map(\.taskId).contains(Column("taskId")))
            .fetchAll(db)
        let sessionByTask = Dictionary(uniqueKeysWithValues: sessions.map { ($0.taskId, $0) })
        return Dictionary(uniqueKeysWithValues: latest.map { row in
            var wrapUp = row.taskWrapUp
            if let session = sessionByTask[row.taskId] {
                wrapUp.outcome = session.outcome
                wrapUp.remainingWork = session.remainingWork
            }
            return (row.taskId, wrapUp)
        })
    }
}
