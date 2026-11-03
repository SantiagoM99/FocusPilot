import Foundation
import GRDB

/// Waiting marks and the tasks a session touched (#57, decision 0004).
extension TaskRepository {
    /// Marks the task waiting, or updates what it waits on and its check,
    /// keeping when it started waiting.
    public func markWaiting(_ taskID: Int64, on: String?, checkAt: Date?) async throws {
        let since = now()
        try await ownerDatabase.write { db in
            try db.execute(sql: """
                INSERT INTO taskWaiting (taskId, waitingOn, since, checkAt) VALUES (?, ?, ?, ?)
                ON CONFLICT(taskId) DO UPDATE SET waitingOn = excluded.waitingOn, checkAt = excluded.checkAt
                """, arguments: [taskID, on, since, checkAt])
        }
    }

    public func stopWaiting(_ taskID: Int64) async throws {
        try await ownerDatabase.write { db in try db.execute(sql: "DELETE FROM taskWaiting WHERE taskId = ?", arguments: [taskID]) }
    }

    /// The task keeps waiting, with no check.
    public func dismissCheck(_ taskID: Int64) async throws {
        try await ownerDatabase.write { db in
            try db.execute(sql: "UPDATE taskWaiting SET checkAt = NULL WHERE taskId = ?", arguments: [taskID])
        }
    }

    public func waitingTasks() async throws -> [TaskWaiting] {
        try await ownerDatabase.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM taskWaiting ORDER BY since, taskId").map {
                TaskWaiting(taskID: $0["taskId"], on: $0["waitingOn"], since: $0["since"], checkAt: $0["checkAt"])
            }
        }
    }

    /// Appends a return cue to the task's wrap-up history, as Switch does.
    public func saveReturnCue(_ cue: String, forTask taskID: Int64, session: UUID?) async throws {
        try await saveWrapUp(WrapUp(returnCue: cue), forTask: taskID, session: session)
    }

    /// The open tasks that became Now during `session`, other than `excluding`,
    /// in the order first touched.
    public func tasksTouched(in session: UUID, excluding: Int64?) async throws -> [TodayItem] {
        let ids = try await ownerDatabase.read { db in
            try Int64.fetchAll(db, sql: """
                SELECT taskId FROM pilotEvent WHERE kind = ? AND sessionId = ? AND taskId IS NOT NULL
                GROUP BY taskId ORDER BY MIN(id)
                """, arguments: [PilotEvent.Kind.taskTouched.rawValue, session.uuidString])
        }
        let open = Dictionary(uniqueKeysWithValues: try await todayTasks().map { ($0.id, $0) })
        return ids.filter { $0 != excluding }.compactMap { open[$0] }
    }
}
