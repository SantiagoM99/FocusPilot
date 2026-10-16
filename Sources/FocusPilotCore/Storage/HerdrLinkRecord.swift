import Foundation
import GRDB

/// A project's link to a Herdr workspace, as stored in the owner database.
struct HerdrLinkRecord: Codable, Equatable, Sendable {
    var projectId: Int64
    var sessionName: String
    var socketPath: String
    var serverStartedAt: Int64
    var workspaceId: String
    var label: String
    var cwd: String?

    init(projectId: Int64, workspace: HerdrWorkspace, server: HerdrServer) {
        self.projectId = projectId
        sessionName = server.sessionName
        socketPath = server.socketPath
        serverStartedAt = server.startedAtMilliseconds
        workspaceId = workspace.id
        label = workspace.label
        cwd = workspace.cwd
    }

    var link: HerdrLink {
        let startedAt = Date(timeIntervalSince1970: Double(serverStartedAt) / 1000)
        return HerdrLink(server: HerdrServer(sessionName: sessionName, socketPath: socketPath, startedAt: startedAt),
                         workspaceID: workspaceId, label: label, cwd: cwd)
    }
}

extension HerdrLinkRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "herdrLink"
}
