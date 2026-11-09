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

    // Review of #63: a Switch note replaces only the return cue; what remains
    // and what got done stay from the last session wrap-up.
    @Test func aSwitchNoteKeepsTheLastWrapUpsRemainingWorkAndOutcome() async throws {
        let current = try await task("Write intro", now: true)
        let target = try await task("Run ablation")
        try await coordinator.startSession(duration: 25 * 60, mode: .normal)
        try await coordinator.complete()
        let ended = try #require(await coordinator.snapshot().session)
        try await coordinator.saveWrapUp(WrapUp(outcome: "Drafted §1", remainingWork: "Cite the 2019 paper",
                                                returnCue: "Start §2"), after: ended)

        _ = try await coordinator.switchTo(target, note: "Halfway through §2", openingAgent: nil)

        let latest = try #require(try await coordinator.todayTasks().first { $0.id == current }?.wrapUp)
        #expect(latest.returnCue == "Halfway through §2" && latest.isFromSwitch)
        #expect(latest.remainingWork == "Cite the 2019 paper" && latest.outcome == "Drafted §1")
        #expect(latest.cueTitle == "Where you left off")
        #expect(try await coordinator.wrapUpHistory(forTask: current).map(\.isFromSwitch) == [true, false])
    }

    // A later session wrap-up that leaves What remains empty means nothing remains.
    @Test func aLaterSessionWrapUpStandsOnItsOwn() async throws {
        let id = try await task("Write intro", now: true)
        for remaining in ["Cite the 2019 paper", nil] {
            try await coordinator.startSession(duration: 25 * 60, mode: .normal)
            try await coordinator.complete()
            let ended = try #require(await coordinator.snapshot().session)
            try await coordinator.saveWrapUp(WrapUp(remainingWork: remaining, returnCue: "Next"), after: ended)
        }

        let latest = try #require(try await coordinator.todayTasks().first { $0.id == id }?.wrapUp)
        #expect(latest.remainingWork == nil && !latest.isFromSwitch && latest.cueTitle == "Start with")
    }

    // Review of #63: from In flight, Switch on a finished thread reviews its result too.
    @Test func switchingFromAFinishedThreadMarksItsResultReviewed() async throws {
        _ = try await task("Write intro", now: true)
        let target = try await task("Run ablation")
        _ = try await coordinator.linkAgent(agent(.working, pane: "w4:p2"), on: herdrServer, workspaceLabel: nil, toTask: target)
        herdr.set(.connected(herdrServer, [agent(.done, pane: "w4:p2")]))
        _ = await coordinator.refreshHerdrAgents()
        let row = try #require(InFlight.board(tasks: try await coordinator.todayTasks(),
                                              links: try await coordinator.agentLinks(),
                                              reviews: try await coordinator.reviewQueue(), waiting: [],
                                              now: clock.now).waitingOnYou.first)
        let request = try #require(row.switchRequest)

        _ = try await coordinator.switchTo(request.taskID, note: nil, openingAgent: request.linkID, handling: request.item)

        #expect(row.status == .resultsReady)
        #expect(try await coordinator.reviewQueue().isEmpty)
    }

    private func linkedAgent(reaching status: HerdrAgentStatus) async throws -> (link: Int64, item: Int64) {
        let target = try await task("Run ablation")
        let link = try await coordinator.linkAgent(agent(.working, pane: "w4:p2"), on: herdrServer, workspaceLabel: nil, toTask: target)
        herdr.set(.connected(herdrServer, [agent(status, pane: "w4:p2")]))
        _ = await coordinator.refreshHerdrAgents()
        return (link.id, try #require(try await coordinator.reviewQueue().first?.id))
    }

    // Decision 0004: a result leaves the queue on Open agent.
    @Test func openingAgentMarksItsResultReviewed() async throws {
        let queued = try await linkedAgent(reaching: .done)

        #expect(await coordinator.openAgent(queued.link, handling: .review(queued.item)) == .opened)

        #expect(try await coordinator.reviewQueue().isEmpty)
    }

    // The owner must still be able to read a result whose agent has gone.
    @Test func aResultStaysWhenItsAgentCouldNotBeOpened() async throws {
        let queued = try await linkedAgent(reaching: .done)
        herdr.set(.connected(herdrServer, []))

        #expect(await coordinator.openAgent(queued.link, handling: .review(queued.item)) == .notFound)

        #expect(try await coordinator.reviewQueue().map(\.id) == [queued.item])
    }

    // FocusPilot never answers approvals: only Herdr's status clears one.
    @Test func openingAnApprovalLeavesItWaitingButEndsTheOwnersWait() async throws {
        let queued = try await linkedAgent(reaching: .blocked)
        clock.set(clock.now.addingTimeInterval(5 * 60))

        #expect(await coordinator.openAgent(queued.link, handling: .review(queued.item)) == .opened)

        #expect(try await coordinator.reviewQueue().map(\.id) == [queued.item])
        let waits = try await coordinator.pilotEvents(since: .distantPast).filter { $0.kind == .agentWait }
        #expect(waits.map(\.duration) == [5 * 60])
    }
}
