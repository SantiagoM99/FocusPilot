import Foundation
import GRDB

/// A linked web page's site, for the session's allowed list (decision 0004).
public struct ContextSite: Equatable, Sendable {
    public var domain: String
    /// The task it is linked to, or the project's tasks.
    public var owner: ResourceOwner
}

extension TaskRepository {
    /// Links a resource. Pages change the session's allowed list, so this
    /// hands out a policy revision in the same write.
    public func addResource(_ target: ResourceTarget, to owner: ResourceOwner) async throws -> (ContextResource, PolicyChange) {
        let createdAt = now()
        return try await ownerDatabase.write { db in
            var row = ResourceRow(owner: owner, target: target, createdAt: createdAt)
            try row.insert(db)
            return (row.resource, PolicyChange(revision: try Self.nextPolicyRevision(db),
                                               inputs: try Self.policyInputs(db, at: createdAt)))
        }
    }

    public func removeResource(_ id: Int64) async throws -> PolicyChange {
        try await policyChange { db in _ = try ResourceRow.deleteOne(db, key: id) }
    }

    /// Saves a folder's new bookmark: followed after a move, or relinked.
    public func updateFolder(_ id: Int64, to bookmark: FolderBookmark) async throws {
        try await ownerDatabase.write { db in
            guard var row = try ResourceRow.fetchOne(db, key: id), row.kind == "folder" else { return }
            row.set(.folder(bookmark))
            try row.update(db)
        }
    }

    /// The task's own resources, then its project's, each oldest first.
    public func resources(forTask taskID: Int64) async throws -> [ContextResource] {
        try await ownerDatabase.read { db in try Self.resources(forTask: taskID, db) }
    }

    public func resource(_ id: Int64) async throws -> ContextResource? {
        try await ownerDatabase.read { db in try ResourceRow.fetchOne(db, key: id)?.resource }
    }

    /// Puts an item at the end of the launch set, or takes it out. Orders
    /// are shared by resources and agents, so one number orders them all.
    public func setLaunch(_ item: ContextItem, included: Bool) async throws {
        try await ownerDatabase.write { db in
            guard included else { return try Self.setLaunchOrder(nil, of: item, db) }
            guard try Self.launchOrder(of: item, db) == nil else { return }
            let last = try Int.fetchOne(db, sql: """
                SELECT MAX(o) FROM (SELECT MAX(launchOrder) AS o FROM resource UNION ALL SELECT MAX(launchOrder) FROM herdrAgentLink)
                """) ?? 0
            try Self.setLaunchOrder(last + 1, of: item, db)
        }
    }

    /// Swaps the item with the one before it in the task's launch set.
    public func moveEarlier(_ item: ContextItem, forTask taskID: Int64) async throws {
        try await ownerDatabase.write { db in
            let set = try Self.launchSet(forTask: taskID, db)
            guard let index = set.firstIndex(where: { $0.item == item }), index > 0 else { return }
            let previous = set[index - 1]
            try Self.setLaunchOrder(previous.order, of: item, db)
            try Self.setLaunchOrder(set[index].order, of: previous.item, db)
        }
    }

    /// The task's launch set in order: its resources, its project's and its agents.
    public func launchSet(forTask taskID: Int64) async throws -> [ContextItem] {
        try await ownerDatabase.read { db in try Self.launchSet(forTask: taskID, db).map(\.item) }
    }

    static func resources(forTask taskID: Int64, _ db: Database) throws -> [ContextResource] {
        let projectID = try Int64.fetchOne(db, sql: "SELECT projectId FROM task WHERE id = ?", arguments: [taskID])
        let own = try ResourceRow.filter(Column("taskId") == taskID).order(Column("id")).fetchAll(db)
        let shared = try projectID.map { try ResourceRow.filter(Column("projectId") == $0).order(Column("id")).fetchAll(db) } ?? []
        return (own + shared).map(\.resource)
    }

    private static func launchSet(forTask taskID: Int64, _ db: Database) throws -> [(item: ContextItem, order: Int)] {
        let resources = try resources(forTask: taskID, db).compactMap { r in r.launchOrder.map { (ContextItem.resource(r.id), $0) } }
        let agents = try HerdrAgentStore.links(forTask: taskID, in: db).compactMap { l in l.launchOrder.map { (ContextItem.agent(l.id), $0) } }
        return (resources + agents).sorted { $0.1 < $1.1 }.map { (item: $0.0, order: $0.1) }
    }

    private static func launchOrder(of item: ContextItem, _ db: Database) throws -> Int? {
        switch item {
        case .resource(let id): try Int.fetchOne(db, sql: "SELECT launchOrder FROM resource WHERE id = ?", arguments: [id])
        case .agent(let id): try Int.fetchOne(db, sql: "SELECT launchOrder FROM herdrAgentLink WHERE id = ?", arguments: [id])
        }
    }

    private static func setLaunchOrder(_ order: Int?, of item: ContextItem, _ db: Database) throws {
        switch item {
        case .resource(let id): try db.execute(sql: "UPDATE resource SET launchOrder = ? WHERE id = ?", arguments: [order, id])
        case .agent(let id): try db.execute(sql: "UPDATE herdrAgentLink SET launchOrder = ? WHERE id = ?", arguments: [order, id])
        }
    }

    /// Every linked page's site, and the project of each task, for the
    /// policy compiled in the same write.
    static func contextSites(_ db: Database) throws -> (sites: [ContextSite], taskProjects: [Int64: Int64]) {
        let sites = try ResourceRow.filter(Column("kind") == "webPage").order(Column("id")).fetchAll(db).map { row in
            ContextSite(domain: WebPageLink(stored: row.url ?? "").domain, owner: row.resource.owner)
        }
        let pairs = try Row.fetchAll(db, sql: "SELECT id, projectId FROM task WHERE projectId IS NOT NULL")
            .map { (row: Row) -> (Int64, Int64) in (row["id"], row["projectId"]) }
        return (sites, Dictionary(uniqueKeysWithValues: pairs))
    }
}
