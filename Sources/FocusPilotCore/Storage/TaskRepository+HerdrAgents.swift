import Foundation
import GRDB

/// Herdr agents linked to tasks, and the Review queue their results go to.
extension TaskRepository {
    /// Links the agent to the task, remembering its current status as the
    /// starting point. Linking it again returns the existing link.
    public func linkAgent(_ agent: HerdrAgent, on server: HerdrServer, workspaceLabel: String?,
                          toTask taskID: Int64) async throws -> TaskAgentLink {
        let linkedAt = now()
        return try await ownerDatabase.write { db in
            try HerdrAgentStore.link(agent, on: server, workspaceLabel: workspaceLabel, toTask: taskID, at: linkedAt, in: db)
        }
    }

    /// Stops watching the agent for this task. Queued items stay.
    public func unlinkAgent(_ linkID: Int64) async throws {
        _ = try await ownerDatabase.write { db in try AgentLinkRow.deleteOne(db, key: linkID) }
    }

    /// The task's links, or every link when `taskID` is nil.
    public func agentLinks(forTask taskID: Int64? = nil) async throws -> [TaskAgentLink] {
        try await ownerDatabase.read { db in try HerdrAgentStore.links(forTask: taskID, in: db) }
    }

    /// Records Herdr's current agents against the links, in one write, and
    /// returns the Review queue items this added.
    public func recordAgents(_ agents: [HerdrAgent], on server: HerdrServer) async throws -> [NewReviewItem] {
        let observedAt = now()
        return try await ownerDatabase.write { db in try HerdrAgentStore.record(agents, on: server, at: observedAt, in: db) }
    }

    public func storeOutput(_ output: AgentOutputPreview, forReviewItem id: Int64) async throws {
        try await ownerDatabase.write { db in try HerdrAgentStore.storeOutput(output, forReviewItem: id, in: db) }
    }

    public func reviewQueue() async throws -> [ReviewItem] {
        try await ownerDatabase.read { db in try HerdrAgentStore.queue(in: db) }
    }

    public func markReviewed(_ id: Int64) async throws {
        let reviewedAt = now()
        try await ownerDatabase.write { db in try HerdrAgentStore.markReviewed(id, at: reviewedAt, in: db) }
    }
}
