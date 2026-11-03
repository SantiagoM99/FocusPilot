import Foundation
import GRDB
import Testing
@testable import FocusPilotCore

/// Decision 0004, End of session: the wrap-up lists every task touched in
/// the session, with one optional line each, kept in the wrap-up history.
@Suite("Wrap-up for every task touched")
struct SessionWrapUpTests {
    private func pin(_ title: String, _ fixture: SessionFixture) async throws -> Int64 {
        try await fixture.coordinator.capture(NewTask(title: title))
        let id = try #require(try await fixture.coordinator.todayTasks().first { $0.title == title }?.id)
        try await fixture.coordinator.moveTask(id, to: .now, .top)
        return id
    }

    /// A session that touched the fixture's task, then two more, and ended on the last.
    private func endedSession(_ fixture: SessionFixture) async throws -> (FocusSession, first: Int64, second: Int64, last: Int64) {
        let first = try #require(try await fixture.coordinator.todayTasks().first?.id)
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)
        let second = try await pin("Reply to Ana", fixture)
        let last = try await pin("Run ablation", fixture)
        try await fixture.coordinator.moveTask(second, to: .now, .top)
        try await fixture.coordinator.moveTask(last, to: .now, .top)
        fixture.advance(minutes: 26)
        try await fixture.coordinator.reconcile()
        return (try #require(await fixture.coordinator.snapshot().session), first, second, last)
    }

    @Test func theOtherTasksTouchedAreListedOnceInTheOrderFirstTouched() async throws {
        let fixture = try await SessionFixture()
        let (ended, first, second, last) = try await endedSession(fixture)

        let others = try await fixture.coordinator.tasksTouched(by: ended)

        #expect(ended.taskID == last)
        #expect(others.map(\.id) == [first, second])
    }

    @Test func aTaskCompletedDuringTheSessionIsNotListed() async throws {
        let fixture = try await SessionFixture()
        let first = try #require(try await fixture.coordinator.todayTasks().first?.id)
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)
        _ = try await pin("Reply to Ana", fixture)
        // Tasks are completed from a wrap-up; here the task is simply marked done.
        try await DatabaseQueue(path: fixture.location.ownerDatabaseURL.path).write { db in
            try db.execute(sql: "UPDATE task SET status = 'done' WHERE id = ?", arguments: [first])
        }
        let session = try #require(await fixture.coordinator.snapshot().session)

        #expect(try await fixture.coordinator.tasksTouched(by: session).isEmpty)
    }

    @Test func eachOtherTaskGetsItsLineAsReturnCueInTheSameSave() async throws {
        let fixture = try await SessionFixture()
        let (ended, first, second, last) = try await endedSession(fixture)

        try await fixture.coordinator.saveWrapUp(WrapUp(outcome: "Table done"), after: ended,
                                                 others: [first: " Check the baseline numbers ", second: "  "])

        let firstCue = try #require(try await fixture.coordinator.wrapUpHistory(forTask: first).first)
        #expect(firstCue.returnCue == "Check the baseline numbers" && firstCue.sessionID == ended.id)
        #expect(try await fixture.coordinator.wrapUpHistory(forTask: second).isEmpty, "A blank line saves nothing")
        #expect(try await fixture.coordinator.wrapUpHistory(forTask: last).first?.outcome == "Table done")
        #expect(try await fixture.coordinator.todayTasks().first { $0.id == first }?.nextAction == "Check the baseline numbers")
    }

    // With nothing in Now at the end, the other tasks are still wrapped up.
    @Test func withNothingInNowTheWrapUpHoldsOnlyTheOtherTasks() throws {
        let running = FocusSession.sample(taskID: nil, action: nil)
        var ended = running
        ended.phase = .ended(at: running.plannedEnd, reason: .reachedPlannedEnd)
        let prompt = try #require(WrapUpPrompt.after(running, ended))

        let alone = PendingWrapUp.receiving(prompt, replacing: nil, task: nil, others: [])
        let withOthers = PendingWrapUp.receiving(prompt, replacing: nil, task: nil, others: [TodayItem(id: 4, title: "Reply to Ana")])

        #expect(!alone.isNeeded)
        #expect(withOthers.isNeeded && withOthers.others.map(\.id) == [4])
    }
}
