import Foundation
import GRDB

/// Adds, undo and reads for the focuspilot CLI. Each function runs inside the
/// caller's single write or read.
enum HerdrTaskStore {
    static func add(_ request: HerdrAddRequest, createdAt: Date, in db: Database) throws -> HerdrAddResult {
        let (newTask, hints) = request.capture
        guard newTask.isValid else { throw NewTask.Invalid.missingTitle }
        let projectID = try request.caller.flatMap { try linkedProjectID(for: $0, in: db) }

        if let stored = try TaskRecord.filter(Column("clientId") == request.id.uuidString).fetchOne(db) {
            return try result(for: stored, request: request, hints: hints, wasAlreadyAdded: true, in: db)
        }
        // Only ever appended: Now, the order of other tasks and every
        // existing task stay exactly as they were.
        let lastRank = try Int.fetchOne(db, sql: "SELECT MAX(rank) FROM task WHERE status = 'next'") ?? -1
        var task = TaskRecord(id: nil, title: newTask.title, projectId: projectID, rank: lastRank + 1,
                              createdAt: createdAt, updatedAt: createdAt)
        task.deadline = newTask.deadline
        task.source = TaskRecord.herdrSource
        task.sourcePane = request.caller?.paneID
        task.clientId = request.id.uuidString
        try task.insert(db)
        return try result(for: task, request: request, hints: hints, wasAlreadyAdded: false, in: db)
    }

    static func undo(_ taskID: Int64, in db: Database) throws {
        guard try TaskRecord.fetchOne(db, key: taskID)?.isFromHerdr == true else { throw HerdrTaskError.notFromHerdr }
        try TaskRecord.deleteOne(db, key: taskID)
    }

    static func scope(for caller: HerdrCaller?, in db: Database) throws -> HerdrTaskScope {
        let open = TaskRecord
            .filter(Column("status") != TaskStatus.done.rawValue)
            .order(sql: "CASE status WHEN 'now' THEN 0 WHEN 'next' THEN 1 ELSE 2 END, rank, id")
        let now = try open.filter(Column("status") == TaskStatus.now.rawValue).fetchOne(db)
        guard let caller, let projectID = try linkedProjectID(for: caller, in: db) else {
            return HerdrTaskScope(now: now.map(scoped), projectTitle: nil, tasks: [])
        }
        return HerdrTaskScope(now: now.map(scoped), projectTitle: try ProjectRecord.fetchOne(db, key: projectID)?.title,
                              tasks: try open.filter(Column("projectId") == projectID).fetchAll(db).map(scoped))
    }

    private static func scoped(_ task: TaskRecord) -> HerdrScopedTask {
        HerdrScopedTask(title: task.title, status: task.status, nextAction: task.nextAction,
                        deadline: task.deadline.map { DeadlineText($0).inspection }, isFromHerdr: task.isFromHerdr)
    }

    private static func result(for task: TaskRecord, request: HerdrAddRequest, hints: [String], wasAlreadyAdded: Bool,
                               in db: Database) throws -> HerdrAddResult {
        let project = try task.projectId.flatMap { try ProjectRecord.fetchOne(db, key: $0) }
        return HerdrAddResult(taskID: task.id!, title: task.title, projectTitle: project?.title,
                              workspaceHasNoProject: request.caller != nil && project == nil,
                              deadlineDescription: task.deadline.map { DeadlineText($0).inspection },
                              hints: hints, wasAlreadyAdded: wasAlreadyAdded)
    }

    /// The project linked to the caller's workspace on the caller's server
    /// instance; a link from before a Herdr restart does not match.
    private static func linkedProjectID(for caller: HerdrCaller, in db: Database) throws -> Int64? {
        try Int64.fetchOne(db, sql: """
            SELECT projectId FROM herdrLink WHERE socketPath = ? AND serverStartedAt = ? AND workspaceId = ?
            """, arguments: [caller.server.socketPath, caller.server.startedAtMilliseconds, caller.workspaceID])
    }
}
