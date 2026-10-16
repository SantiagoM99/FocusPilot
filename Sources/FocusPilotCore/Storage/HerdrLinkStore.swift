import Foundation
import GRDB

/// The Herdr link writes. Each function runs inside the caller's single
/// write, so a project and its link always commit together.
enum HerdrLinkStore {
    /// Links each workspace that has no project yet; already linked ones are
    /// left alone, so importing twice changes nothing.
    static func importWorkspaces(_ workspaces: [HerdrWorkspace], on server: HerdrServer, in db: Database) throws {
        for workspace in workspaces {
            try markSeen(workspace, on: server, in: db)
            if try linkedProjectID(workspace, on: server, in: db) == nil {
                try linkNewOrMatchingProject(to: workspace, on: server, in: db)
            }
        }
    }

    /// Turns the workspaces that appeared since the last sync into linked
    /// projects, and returns their titles.
    static func syncWorkspaces(_ workspaces: [HerdrWorkspace], on server: HerdrServer, in db: Database) throws -> [String] {
        guard try isSeen(server, in: db) else {
            // The first sight of a server instance: what is open now was
            // opened before FocusPilot was watching, or is the same work
            // renumbered by a restart. Import covers those on request.
            try db.execute(sql: "INSERT INTO herdrSeenServer (socketPath, serverStartedAt) VALUES (?, ?)",
                           arguments: [server.socketPath, server.startedAtMilliseconds])
            for workspace in workspaces { try markSeen(workspace, on: server, in: db) }
            return []
        }
        var created: [String] = []
        for workspace in workspaces {
            guard try !isSeen(workspace, on: server, in: db) else { continue }
            try markSeen(workspace, on: server, in: db)
            let isLinked = try linkedProjectID(workspace, on: server, in: db) != nil
            if workspace.isLinkedWorktree || isLinked { continue }
            created.append(try linkNewOrMatchingProject(to: workspace, on: server, in: db))
        }
        return created
    }

    /// Links or relinks one project, replacing any link it had.
    static func link(project projectID: Int64, to workspace: HerdrWorkspace, on server: HerdrServer, in db: Database) throws {
        if let owner = try linkedProjectID(workspace, on: server, in: db), owner != projectID {
            throw HerdrLinkError.workspaceAlreadyLinked
        }
        try HerdrLinkRecord.deleteOne(db, key: projectID)
        try HerdrLinkRecord(projectId: projectID, workspace: workspace, server: server).insert(db)
        try markSeen(workspace, on: server, in: db)
    }

    /// A project named after the workspace: an unlinked project with that
    /// name if there is one, else a new project, numbered if the name is
    /// taken. Returns the project's title.
    @discardableResult
    private static func linkNewOrMatchingProject(to workspace: HerdrWorkspace, on server: HerdrServer,
                                                 in db: Database) throws -> String {
        let name = workspace.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseTitle = name.isEmpty ? "Workspace \(workspace.id)" : name
        let projects = try ProjectRecord.fetchAll(db)
        let linked = Set(try Int64.fetchAll(db, sql: "SELECT projectId FROM herdrLink"))
        func existing(_ title: String) -> ProjectRecord? {
            projects.first { $0.title.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        }

        var project: ProjectRecord
        if let match = existing(baseTitle), !linked.contains(match.id!) {
            project = match
        } else {
            let title = (2...).lazy.map { "\(baseTitle) \($0)" }.first { existing($0) == nil }!
            project = ProjectRecord(id: nil, title: existing(baseTitle) == nil ? baseTitle : title)
            try project.insert(db)
        }
        try HerdrLinkRecord(projectId: project.id!, workspace: workspace, server: server).insert(db)
        return project.title
    }

    private static func linkedProjectID(_ workspace: HerdrWorkspace, on server: HerdrServer, in db: Database) throws -> Int64? {
        try Int64.fetchOne(db, sql: """
            SELECT projectId FROM herdrLink WHERE socketPath = ? AND serverStartedAt = ? AND workspaceId = ?
            """, arguments: [server.socketPath, server.startedAtMilliseconds, workspace.id])
    }

    private static func isSeen(_ server: HerdrServer, in db: Database) throws -> Bool {
        try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM herdrSeenServer WHERE socketPath = ? AND serverStartedAt = ?)",
                          arguments: [server.socketPath, server.startedAtMilliseconds])!
    }

    private static func isSeen(_ workspace: HerdrWorkspace, on server: HerdrServer, in db: Database) throws -> Bool {
        try Bool.fetchOne(db, sql: """
            SELECT EXISTS (SELECT 1 FROM herdrSeenWorkspace WHERE socketPath = ? AND serverStartedAt = ? AND workspaceId = ?)
            """, arguments: [server.socketPath, server.startedAtMilliseconds, workspace.id])!
    }

    private static func markSeen(_ workspace: HerdrWorkspace, on server: HerdrServer, in db: Database) throws {
        try db.execute(sql: """
            INSERT OR IGNORE INTO herdrSeenWorkspace (socketPath, serverStartedAt, workspaceId) VALUES (?, ?, ?)
            """, arguments: [server.socketPath, server.startedAtMilliseconds, workspace.id])
    }
}
