import Foundation
import Testing
@testable import FocusPilotCore

@Suite("Focus sessions through the coordinator")
struct FocusSessionCoordinatorTests {
    @Test func startingNeedsAPinnedNowTask() async throws {
        let coordinator = FocusCoordinator(repository: try TaskRepository(location: StorageLocation(directory: makeTemporaryDirectory())))

        await #expect(throws: FocusCoordinator.SessionError.noCurrentTask) {
            try await coordinator.startSession(duration: 25 * 60, mode: .normal)
        }
    }

    @Test func startingRunsTheNowTaskAndPublishesAWrappedPolicy() async throws {
        let fixture = try await SessionFixture()

        try await fixture.coordinator.startSession(duration: 50 * 60, mode: .normal)

        let session = try #require(await fixture.coordinator.snapshot().activeSession)
        #expect(session.action == "Explain baseline results")
        #expect(session.plannedEnd == wednesdayMorningInBogota.addingTimeInterval(50 * 60))
        let policy = try #require(await fixture.publisher.published.last)
        #expect(policy.schemaVersion == PublishedPolicy.currentSchemaVersion)
        #expect(policy.revision == 1)
        #expect(policy.effectiveAt == wednesdayMorningInBogota)
        #expect(policy.session?.end == session.plannedEnd)
    }

    @Test func pausingKeepsThePlannedEndAndLiftsNormalRules() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)
        fixture.advance(minutes: 5)

        try await fixture.coordinator.pause()

        let session = try #require(await fixture.coordinator.snapshot().activeSession)
        #expect(session.plannedEnd == wednesdayMorningInBogota.addingTimeInterval(25 * 60))
        #expect(await fixture.publisher.published.last?.session == nil)
        try await fixture.coordinator.resume()
        #expect(await fixture.publisher.published.last?.session != nil)
    }

    @Test func strictPauseKeepsTheRules() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .strict)

        try await fixture.coordinator.pause()

        #expect(await fixture.publisher.published.last?.session?.mode == .strict)
    }

    @Test func relaunchingMidSessionRestoresTheRemainingTime() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)
        fixture.advance(minutes: 10)

        let relaunched = try fixture.relaunched()
        try await relaunched.launch()

        let session = try #require(await relaunched.snapshot().activeSession)
        #expect(session.plannedEnd.timeIntervalSince(fixture.clock.now) == 15 * 60)
        #expect(await fixture.publisher.published.map(\.revision) == [1, 2])
    }

    @Test func relaunchingAfterThePlannedEndRecordsTheEndAndTellsTheOwner() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)
        fixture.advance(minutes: 90)

        let relaunched = try fixture.relaunched()
        try await relaunched.launch()

        let session = try #require(await relaunched.snapshot().session)
        #expect(session.phase == .ended(at: session.plannedEnd, reason: .reachedPlannedEnd))
        #expect(await relaunched.snapshot().activeSession == nil)
        #expect(await fixture.publisher.published.last?.session == nil)
        #expect(await fixture.notices.delivered == [.sessionReachedPlannedEnd])
    }

    @Test func reconcilingAtThePlannedEndEndsTheSession() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)
        #expect(await fixture.coordinator.snapshot().nextDeadline == wednesdayMorningInBogota.addingTimeInterval(25 * 60))
        fixture.advance(minutes: 25)

        try await fixture.coordinator.reconcile()

        #expect(await fixture.coordinator.snapshot().activeSession == nil)
        #expect(await fixture.coordinator.snapshot().nextDeadline == nil)
    }

    @Test func completingANormalSessionEndsItRightAway() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)
        fixture.advance(minutes: 3)

        let result = try await fixture.coordinator.complete()

        #expect(result == .completed)
        #expect(await fixture.coordinator.snapshot().session?.phase == .ended(at: fixture.clock.now, reason: .completed))
    }

    @Test func startingAgainWhileASessionRunsIsRefused() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)

        await #expect(throws: FocusEngineError.sessionAlreadyActive) {
            try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)
        }
    }
}

@Suite("Ending a strict session early")
struct StrictEarlyEndTests {
    // Proposed value awaiting owner sign-off (decision 0003, 2026-10-14).
    @Test func theWaitIsSixtySeconds() {
        #expect(StrictEarlyEnd.wait == 60)
    }

    @Test func completingEarlyAsksToWaitAndKeepsTheSessionRunning() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .strict)
        fixture.advance(minutes: 5)
        let requestedAt = fixture.clock.now

        let first = try await fixture.coordinator.complete()

        #expect(first == .waitUntil(requestedAt.addingTimeInterval(StrictEarlyEnd.wait)))
        #expect(await fixture.coordinator.snapshot().activeSession != nil)
        #expect(await fixture.coordinator.snapshot().earlyEndAvailableAt == requestedAt.addingTimeInterval(StrictEarlyEnd.wait))
        fixture.advance(minutes: 0.5)
        #expect(try await fixture.coordinator.complete() == .waitUntil(requestedAt.addingTimeInterval(StrictEarlyEnd.wait)))
    }

    @Test func completingAfterTheWaitEndsTheSession() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .strict)
        _ = try await fixture.coordinator.complete()
        fixture.advance(minutes: 1)

        #expect(try await fixture.coordinator.complete() == .completed)
        #expect(await fixture.coordinator.snapshot().activeSession == nil)
        #expect(await fixture.coordinator.snapshot().earlyEndAvailableAt == nil)
    }

    @Test func cancellingTheEarlyEndStartsTheWaitOver() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .strict)
        _ = try await fixture.coordinator.complete()
        fixture.advance(minutes: 1)

        await fixture.coordinator.cancelEarlyEnd()

        #expect(await fixture.coordinator.snapshot().earlyEndAvailableAt == nil)
        #expect(try await fixture.coordinator.complete() == .waitUntil(fixture.clock.now.addingTimeInterval(StrictEarlyEnd.wait)))
    }

    @Test func aStrictSessionPastItsPlannedEndCompletesWithoutWaiting() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .strict)
        fixture.advance(minutes: 26)

        #expect(try await fixture.coordinator.complete() == .completed)
    }
}

@Suite("Snapshot stream")
struct SnapshotStreamTests {
    @Test func subscribersSeeSessionAndNowChanges() async throws {
        let fixture = try await SessionFixture()
        let stream = await fixture.coordinator.snapshots()
        var iterator = stream.makeAsyncIterator()

        #expect(await iterator.next()?.currentTaskTitle == "Explain baseline results")
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)
        #expect(await iterator.next()?.activeSession != nil)
        try await fixture.coordinator.capture(NewTask(title: "Reply to co-advisor"))
        let next = try await fixture.coordinator.todayTasks().last!.id
        try await fixture.coordinator.moveTask(next, to: .now, .top)
        var latest = await iterator.next()
        while latest?.currentTaskTitle != "Reply to co-advisor" { latest = await iterator.next() }
        #expect(latest?.activeSession != nil)
    }
}
