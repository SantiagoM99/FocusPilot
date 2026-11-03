import Foundation
import GRDB
import Testing
@testable import FocusPilotCore

/// Decision 0004: Switch asks where the owner left off, saves it as the
/// current task's return cue, makes the target Now, then opens its agent,
/// all on the owner's one click. Nothing here happens on its own.
@Suite("Switch and waiting threads")
struct SwitchTests {
    private let location: StorageLocation
    private let clock = SettableClock(wednesdayMorningInBogota)
    private let herdr = FakeHerdrAgents(.connected(herdrServer, [agent(.working, pane: "w4:p2")]))
    private let coordinator: FocusCoordinator

    init() throws {
        location = StorageLocation(directory: try makeTemporaryDirectory())
        let clock = clock
        coordinator = FocusCoordinator(repository: try TaskRepository(location: location, now: { clock.now }),
                                       agents: herdr, now: { clock.now })
    }

    private func task(_ title: String, now: Bool = false) async throws -> Int64 {
        try await coordinator.capture(NewTask(title: title))
        let id = try #require(try await coordinator.todayTasks().first { $0.title == title }?.id)
        if now { try await coordinator.moveTask(id, to: .now, .top) }
        return id
    }

    private var nowID: Int64? {
        get async throws { try await coordinator.todayTasks().first { $0.status == .now }?.id }
    }

    @Test func switchingSavesTheNoteMakesTheTargetNowThenOpensItsAgent() async throws {
        let current = try await task("Write intro", now: true)
        let target = try await task("Run ablation")
        let link = try await coordinator.linkAgent(agent(.working, pane: "w4:p2"), on: herdrServer, workspaceLabel: nil,
                                                   toTask: target)

        let opened = try await coordinator.switchTo(target, note: "  Second paragraph, after the table ", openingAgent: link.id)

        #expect(opened == .opened)
        #expect(try await nowID == target)
        let cue = try #require(try await coordinator.wrapUpHistory(forTask: current).first)
        #expect(cue.returnCue == "Second paragraph, after the table" && cue.outcome == nil && cue.sessionID == nil)
        #expect(try await coordinator.todayTasks().first { $0.id == current }?.nextAction == "Second paragraph, after the table")
        #expect(herdr.calls.last == .focus("w4:p2"), "The agent opens last")
    }

    @Test func aBlankNoteSavesNothingAndNoAgentOpensUnlessAsked() async throws {
        let current = try await task("Write intro", now: true)
        let target = try await task("Run ablation")
        _ = try await coordinator.linkAgent(agent(.working, pane: "w4:p2"), on: herdrServer, workspaceLabel: nil, toTask: target)

        #expect(try await coordinator.switchTo(target, note: "   ", openingAgent: nil) == nil)

        #expect(try await coordinator.wrapUpHistory(forTask: current).isEmpty)
        #expect(!herdr.calls.contains(.focus("w4:p2")))
        #expect(try await nowID == target)
    }

    @Test func duringASessionTheNoteBelongsToItAndTheSessionFollowsNow() async throws {
        let current = try await task("Write intro", now: true)
        let target = try await task("Run ablation")
        try await coordinator.startSession(duration: 25 * 60, mode: .normal)
        let session = try #require(await coordinator.snapshot().activeSession)

        _ = try await coordinator.switchTo(target, note: "After the table", openingAgent: nil)

        #expect(try await coordinator.wrapUpHistory(forTask: current).first?.sessionID == session.id)
        #expect(await coordinator.snapshot().activeSession?.taskID == target)
    }

    @Test func switchingToAResultMarksItReviewedButAnApprovalStaysUntilAnswered() async throws {
        _ = try await task("Write intro", now: true)
        let target = try await task("Run ablation")
        let link = try await coordinator.linkAgent(agent(.working, pane: "w4:p2"), on: herdrServer, workspaceLabel: nil,
                                                   toTask: target)
        herdr.set(.connected(herdrServer, [agent(.done, pane: "w4:p2")]))
        _ = await coordinator.refreshHerdrAgents()
        let result = try #require(try await coordinator.reviewQueue().first)

        _ = try await coordinator.switchTo(target, note: nil, openingAgent: link.id, handling: .review(result.id))

        #expect(try await coordinator.reviewQueue().isEmpty)
    }

    @Test func aTaskMarkedWaitingIsStoredAndItsCheckCanBeDismissed() async throws {
        let id = try await task("Send the draft")
        let check = clock.now.addingTimeInterval(3600)

        try await coordinator.markWaiting(id, on: " Ana's review ", checkAt: check)
        #expect(try await coordinator.waitingTasks() == [TaskWaiting(taskID: id, on: "Ana's review", since: clock.now, checkAt: check)])

        try await coordinator.dismissCheck(id)
        #expect(try await coordinator.waitingTasks().first?.checkAt == nil)

        try await coordinator.stopWaiting(id)
        #expect(try await coordinator.waitingTasks().isEmpty)
    }

    // Switching to a task to check on it means the owner is on it now.
    @Test func switchingToADueCheckEndsTheWait() async throws {
        _ = try await task("Write intro", now: true)
        let id = try await task("Send the draft")
        try await coordinator.markWaiting(id, on: nil, checkAt: clock.now)

        _ = try await coordinator.switchTo(id, note: nil, openingAgent: nil, handling: .check(id))

        #expect(try await coordinator.waitingTasks().isEmpty)
    }

    // Decision 0004: FocusPilot never changes Now by itself.
    @Test func resultsApprovalsAndDueChecksNeverChangeNow() async throws {
        let current = try await task("Write intro", now: true)
        let other = try await task("Run ablation")
        _ = try await coordinator.linkAgent(agent(.working, pane: "w4:p2"), on: herdrServer, workspaceLabel: nil, toTask: other)
        try await coordinator.markWaiting(other, on: nil, checkAt: clock.now)
        herdr.set(.connected(herdrServer, [agent(.blocked, pane: "w4:p2")]))

        _ = await coordinator.refreshHerdrAgents()
        clock.set(clock.now.addingTimeInterval(3 * 3600))

        #expect(try await nowID == current)
        #expect(!herdr.calls.contains(.focus("w4:p2")))
    }

    @Test func waitingMarksGoWithTheirTask() async throws {
        let id = try await task("Send the draft")
        try await coordinator.markWaiting(id, on: nil, checkAt: nil)

        try await DatabaseQueue(path: location.ownerDatabaseURL.path).write { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(sql: "DELETE FROM task WHERE id = ?", arguments: [id])
        }

        #expect(try await coordinator.waitingTasks().isEmpty)
    }
}
