import Foundation
import Testing
@testable import FocusPilotCore

@Suite("Wrap-up through the coordinator")
struct WrapUpCoordinatorTests {
    private let wrapUp = WrapUp(outcome: "Drafted §4.2", remainingWork: "Ablation sentence", returnCue: "Check Table 3")

    @Test func savingAfterASessionEndsKeepsItInHistoryAndUpdatesTheSnapshot() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)
        fixture.advance(minutes: 25)
        try await fixture.coordinator.reconcile()
        let ended = try #require(await fixture.coordinator.snapshot().session)
        let revisionBefore = await fixture.coordinator.snapshot().revision

        try await fixture.coordinator.saveWrapUp(wrapUp, after: ended, markingDone: true)

        let snapshot = await fixture.coordinator.snapshot()
        #expect(snapshot.currentTaskTitle == nil)
        #expect(snapshot.revision > revisionBefore)
        #expect(try await fixture.coordinator.wrapUpHistory(forTask: ended.taskID).map(\.sessionID) == [ended.id])
    }

    @Test func aSessionStillRunningOrPausedCannotBeWrappedUp() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)
        let running = try #require(await fixture.coordinator.snapshot().activeSession)
        try await fixture.coordinator.pause()
        let paused = try #require(await fixture.coordinator.snapshot().activeSession)

        for session in [running, paused] {
            await #expect(throws: FocusCoordinator.SessionError.sessionStillActive) {
                try await fixture.coordinator.saveWrapUp(wrapUp, after: session)
            }
        }
        #expect(try await fixture.coordinator.wrapUpHistory(forTask: running.taskID).isEmpty)
    }

    @Test func anEndedSessionCannotMarkItsTaskDoneWhileANewSessionRunsOnIt() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)
        fixture.advance(minutes: 25)
        try await fixture.coordinator.reconcile()
        let first = try #require(await fixture.coordinator.snapshot().session)
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)
        let second = try #require(await fixture.coordinator.snapshot().activeSession)
        #expect(second.taskID == first.taskID)

        await #expect(throws: FocusCoordinator.SessionError.sessionStillActive) {
            try await fixture.coordinator.saveWrapUp(wrapUp, after: first, markingDone: true)
        }
        #expect(await fixture.coordinator.snapshot().currentTaskTitle != nil)
        #expect(try await fixture.coordinator.wrapUpHistory(forTask: first.taskID).isEmpty)

        try await fixture.coordinator.saveWrapUp(wrapUp, after: first)
        #expect(try await fixture.coordinator.wrapUpHistory(forTask: first.taskID).map(\.sessionID) == [first.id])
    }
}
