import Foundation
import Testing
@testable import FocusPilotCore

/// #58: how long an agent waited for the owner, from when FocusPilot saw it
/// ask or finish until the owner switched to it or reviewed it. Recorded
/// once per item, as a pilot event.
@Suite("Agent waits")
struct AgentWaitTests {
    private let clock = SettableClock(wednesdayMorningInBogota)
    private let herdr = FakeHerdrAgents(.connected(herdrServer, [agent(.working, pane: "w4:p2")]))
    private let coordinator: FocusCoordinator

    init() throws {
        let clock = clock
        coordinator = FocusCoordinator(repository: try TaskRepository(location: StorageLocation(directory: makeTemporaryDirectory()),
                                                                      now: { clock.now }),
                                       agents: herdr, now: { clock.now })
    }

    /// A task whose agent then reaches `status`, queuing an item.
    private func queued(_ status: HerdrAgentStatus) async throws -> (task: Int64, link: Int64, item: ReviewItem) {
        let task = try await coordinator.repository.addTask(NewTask(title: "Run ablation")).id!
        let link = try await coordinator.linkAgent(agent(.working, pane: "w4:p2"), on: herdrServer, workspaceLabel: nil, toTask: task)
        herdr.set(.connected(herdrServer, [agent(status, pane: "w4:p2")]))
        _ = await coordinator.refreshHerdrAgents()
        return (task, link.id, try #require(try await coordinator.reviewQueue().first))
    }

    private var waits: [PilotEvent] {
        get async throws { try await coordinator.pilotEvents(since: .distantPast).filter { $0.kind == .agentWait } }
    }

    @Test func reviewingAResultRecordsHowLongItWaited() async throws {
        let (task, _, item) = try await queued(.done)
        clock.set(clock.now.addingTimeInterval(14 * 60))

        try await coordinator.markReviewed(item.id)
        try await coordinator.markReviewed(item.id)

        #expect(try await waits == [PilotEvent(kind: .agentWait, at: clock.now, duration: 14 * 60, target: "finished", taskID: task)])
    }

    // An approval is answered in Herdr, but the wait ends when the owner switched to it.
    @Test func switchingToAnApprovalEndsItsWaitOnce() async throws {
        let (task, link, item) = try await queued(.blocked)
        clock.set(clock.now.addingTimeInterval(5 * 60))

        _ = try await coordinator.switchTo(task, note: nil, openingAgent: link, handling: .review(item.id))
        clock.set(clock.now.addingTimeInterval(60))
        _ = try await coordinator.switchTo(task, note: nil, openingAgent: link, handling: .review(item.id))

        #expect(try await waits.map(\.duration) == [5 * 60])
        #expect(try await waits.first?.target == "approval")
        #expect(try await coordinator.reviewQueue().map(\.id) == [item.id], "The approval stays until answered")
    }

    // Review of #65: answered in Herdr, the same agent still in its pane: the
    // wait counts, marked as answered there.
    @Test func anApprovalAnsweredInHerdrCountsWithItsOwnSource() async throws {
        let (task, _, _) = try await queued(.blocked)
        clock.set(clock.now.addingTimeInterval(9 * 60))
        herdr.set(.connected(herdrServer, [agent(.working, pane: "w4:p2")]))

        _ = await coordinator.refreshHerdrAgents()

        #expect(try await waits == [PilotEvent(kind: .agentWait, at: clock.now, duration: 9 * 60, target: "approvalInHerdr", taskID: task)])
    }

    @Test func anApprovalWhosePaneClosedIsNotCounted() async throws {
        _ = try await queued(.blocked)
        herdr.set(.connected(herdrServer, []))

        _ = await coordinator.refreshHerdrAgents()

        #expect(try await coordinator.reviewQueue().isEmpty)
        #expect(try await waits.isEmpty)
    }

    @Test func anApprovalSwitchedToAndThenAnsweredCountsOnce() async throws {
        let (task, link, item) = try await queued(.blocked)
        clock.set(clock.now.addingTimeInterval(2 * 60))
        _ = try await coordinator.switchTo(task, note: nil, openingAgent: link, handling: .review(item.id))
        herdr.set(.connected(herdrServer, [agent(.working, pane: "w4:p2")]))

        _ = await coordinator.refreshHerdrAgents()

        #expect(try await waits.map(\.target) == ["approval"])
    }
}
