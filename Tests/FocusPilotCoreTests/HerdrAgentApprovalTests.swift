import Foundation
import Testing
@testable import FocusPilotCore

/// When a "Needs your approval" item appears and when it goes away.
@Suite("Herdr agents on tasks: approval items")
struct HerdrAgentApprovalTests {
    private let repository: TaskRepository

    init() throws {
        repository = try TaskRepository(location: StorageLocation(directory: makeTemporaryDirectory()))
    }

    private func linkedTask(_ status: HerdrAgentStatus) async throws -> TaskAgentLink {
        let taskID = try await repository.addTask(NewTask(title: "Explain baseline results")).id!
        return try await repository.linkAgent(agent(status), on: herdrServer, workspaceLabel: "NLP report",
                                              toTask: taskID)
    }

    private var queuedKinds: [AgentTransition.Review] {
        get async throws { try await repository.reviewQueue().map(\.kind) }
    }

    @Test func linkingAnAgentAlreadyWaitingQueuesItsApprovalOnce() async throws {
        let link = try await linkedTask(.blocked)
        #expect(try await queuedKinds == [.approval])
        #expect(try await repository.reviewQueue().first?.linkID == link.id)

        #expect(try await repository.recordAgents([agent(.blocked)], on: herdrServer).isEmpty)
        _ = try await repository.linkAgent(agent(.blocked), on: herdrServer, workspaceLabel: nil, toTask: link.taskID)
        #expect(try await queuedKinds == [.approval])
    }

    @Test func anApprovalFoundAtLinkTimeIsAnsweredLikeAnyOther() async throws {
        _ = try await linkedTask(.blocked)
        _ = try await repository.recordAgents([agent(.idle)], on: herdrServer)
        #expect(try await queuedKinds == [.finished])
    }

    @Test func unlinkingClearsItsUnansweredApproval() async throws {
        let link = try await linkedTask(.working)
        _ = try await repository.recordAgents([agent(.blocked)], on: herdrServer)

        try await repository.unlinkAgent(link.id)

        #expect(try await repository.reviewQueue().isEmpty)
    }

    @Test func unlinkingKeepsReadyResults() async throws {
        let link = try await linkedTask(.working)
        _ = try await repository.recordAgents([agent(.idle)], on: herdrServer)
        try await repository.unlinkAgent(link.id)
        #expect(try await queuedKinds == [.finished])
    }

    @Test func anApprovalIsClearedWhenItsPaneIsGoneOrHoldsAnotherAgent() async throws {
        let gone = try await linkedTask(.blocked)
        _ = try await repository.recordAgents([], on: herdrServer)
        #expect(try await repository.reviewQueue().isEmpty)

        let replaced = try await repository.linkAgent(agent(.blocked, pane: "w4:p3"), on: herdrServer,
                                                      workspaceLabel: nil, toTask: gone.taskID)
        _ = try await repository.recordAgents([agent(.blocked, pane: replaced.paneID, kind: "codex")], on: herdrServer)
        #expect(try await repository.reviewQueue().isEmpty)
    }

    @Test func anApprovalIsClearedAfterAHerdrRestart() async throws {
        _ = try await linkedTask(.blocked)
        _ = try await repository.recordAgents([agent(.blocked)], on: restartedHerdrServer)
        #expect(try await repository.reviewQueue().isEmpty)
    }

    @Test func aRenamedAgentKeepsItsApproval() async throws {
        // Probably the same agent; the owner can relink it.
        _ = try await linkedTask(.blocked)
        _ = try await repository.recordAgents([agent(.blocked, name: "ablation-2")], on: herdrServer)
        #expect(try await queuedKinds == [.approval])
    }
}
