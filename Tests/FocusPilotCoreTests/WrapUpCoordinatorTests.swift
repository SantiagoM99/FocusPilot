import Foundation
import Testing
@testable import FocusPilotCore

@Suite("Wrap-up through the coordinator")
struct WrapUpCoordinatorTests {
    private let wrapUp = WrapUp(outcome: "Drafted §4.2", remainingWork: "Ablation sentence", returnCue: "Check Table 3")

    @Test func savingAfterASessionEndsUpdatesTheTaskAndTheSnapshot() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)
        fixture.advance(minutes: 25)
        try await fixture.coordinator.reconcile()
        let taskID = try #require(await fixture.coordinator.snapshot().session?.taskID)
        let revisionBefore = await fixture.coordinator.snapshot().revision

        try await fixture.coordinator.saveWrapUp(wrapUp, forTask: taskID, markingDone: true)

        let snapshot = await fixture.coordinator.snapshot()
        #expect(snapshot.currentTaskTitle == nil)
        #expect(snapshot.revision > revisionBefore)
        #expect(try await fixture.coordinator.todayTasks().isEmpty)
    }

    @Test func savingWhilePausedKeepsTheSessionAndTheTaskOpen() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)
        try await fixture.coordinator.pause()
        let session = try #require(await fixture.coordinator.snapshot().activeSession)

        try await fixture.coordinator.saveWrapUp(wrapUp, forTask: session.taskID)

        #expect(await fixture.coordinator.snapshot().activeSession == session)
        #expect(try await fixture.coordinator.todayTasks().first?.wrapUp?.returnCue == "Check Table 3")
    }

    @Test func aTaskCannotBeMarkedDoneWhileItsSessionIsActive() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .strict)
        try await fixture.coordinator.pause()
        let session = try #require(await fixture.coordinator.snapshot().activeSession)

        await #expect(throws: FocusCoordinator.SessionError.sessionStillActive) {
            try await fixture.coordinator.saveWrapUp(wrapUp, forTask: session.taskID, markingDone: true)
        }
        #expect(try await fixture.coordinator.todayTasks().first?.wrapUp == nil)
    }
}
