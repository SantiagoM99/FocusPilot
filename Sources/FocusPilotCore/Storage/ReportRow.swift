import Foundation
import GRDB

/// An agent report as stored. A proposal's target is spread over columns
/// like a linked agent's: its server instance, pane, name and program.
struct ReportRow: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "agentReport"

    var id: Int64?
    var clientId: String
    var summary: String
    var projectId: Int64?
    var sourceLabel: String
    var message: String?
    var targetGiven: String?
    var targetSession: String?
    var targetSocket: String?
    var targetStartedAt: Int64?
    var targetPane: String?
    var targetName: String?
    var targetKind: String?
    var targetProblem: String?
    var receivedAt: Date
    /// When Accept sent the message; the row stays as a record of it.
    var sentAt: Date?

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var target: ReportTarget? {
        guard let targetSession, let targetSocket, let targetStartedAt, let targetPane, let targetKind else { return nil }
        let server = HerdrServer(sessionName: targetSession, socketPath: targetSocket,
                                 startedAt: Date(timeIntervalSince1970: Double(targetStartedAt) / 1000))
        return ReportTarget(server: server, paneID: targetPane, name: targetName, kind: targetKind)
    }

    func report(projectTitle: String?) -> AgentReport {
        let proposal = message.map { ReportProposal(message: $0, targetAsGiven: targetGiven ?? "", target: target,
                                                    targetProblem: targetProblem) }
        return AgentReport(id: id!, clientID: UUID(uuidString: clientId)!, summary: summary, projectID: projectId,
                           projectTitle: projectTitle, sourceLabel: sourceLabel, proposal: proposal, receivedAt: receivedAt)
    }
}
