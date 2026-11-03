import Foundation
import GRDB

extension TaskRepository {
    /// Stores a report, once per request ID. The project is the one named,
    /// matched like captures (ignoring case and accents) but never created,
    /// else the one linked to the caller's workspace.
    public func addReport(_ request: ReportRequest, sourceLabel: String,
                          target: Result<ReportTarget, ReportTargetProblem>?) async throws -> ReportReceipt {
        let receivedAt = now()
        return try await ownerDatabase.write { db in
            if let existing = try ReportRow.filter(Column("clientId") == request.id.uuidString).fetchOne(db) {
                return ReportReceipt(wasAlreadyReceived: true, projectTitle: try Self.projectTitle(existing.projectId, db),
                                     targetProblem: existing.targetProblem)
            }
            var notes: [String] = []
            var projectID: Int64?
            if let name = request.project {
                projectID = try ProjectRecord.fetchAll(db).first {
                    $0.title.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                }?.id
                if projectID == nil { notes.append("No project is named “\(name)”, so the report has no project.") }
            } else if let caller = request.caller {
                projectID = try Int64.fetchOne(db, sql: """
                    SELECT projectId FROM herdrLink WHERE socketPath = ? AND serverStartedAt = ? AND workspaceId = ?
                    """, arguments: [caller.server.socketPath, caller.server.startedAtMilliseconds, caller.workspaceID])
            }
            var row = ReportRow(id: nil, clientId: request.id.uuidString, summary: request.summary, projectId: projectID,
                                sourceLabel: sourceLabel, message: request.message, targetGiven: request.to,
                                receivedAt: receivedAt)
            switch target {
            case .success(let target)?:
                row.targetSession = target.server.sessionName
                row.targetSocket = target.server.socketPath
                row.targetStartedAt = target.server.startedAtMilliseconds
                row.targetPane = target.paneID
                row.targetName = target.name
                row.targetKind = target.kind
            case .failure(let problem)?:
                row.targetProblem = problem.text
            case nil:
                break
            }
            try row.insert(db)
            return ReportReceipt(wasAlreadyReceived: false, projectTitle: try Self.projectTitle(projectID, db),
                                 targetProblem: row.targetProblem, notes: notes)
        }
    }

    /// Reports not yet sent or dismissed, oldest first.
    public func reports() async throws -> [AgentReport] {
        try await ownerDatabase.read { db in
            try ReportRow.filter(Column("sentAt") == nil).order(Column("id")).fetchAll(db).map {
                $0.report(projectTitle: try Self.projectTitle($0.projectId, db))
            }
        }
    }

    public func report(_ id: Int64) async throws -> AgentReport? {
        try await ownerDatabase.read { db in
            try ReportRow.filter(Column("id") == id && Column("sentAt") == nil).fetchOne(db)
                .map { $0.report(projectTitle: try Self.projectTitle($0.projectId, db)) }
        }
    }

    public func markReportSent(_ id: Int64) async throws {
        let sentAt = now()
        try await ownerDatabase.write { db in
            try db.execute(sql: "UPDATE agentReport SET sentAt = ? WHERE id = ?", arguments: [sentAt, id])
        }
    }

    /// Dismiss discards the report.
    public func removeReport(_ id: Int64) async throws {
        _ = try await ownerDatabase.write { db in try ReportRow.deleteOne(db, key: id) }
    }

    private static func projectTitle(_ id: Int64?, _ db: Database) throws -> String? {
        try id.flatMap { try String.fetchOne(db, sql: "SELECT title FROM project WHERE id = ?", arguments: [$0]) }
    }
}
