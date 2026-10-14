import Foundation
import Testing
@testable import FocusPilotCore

@Suite("FocusEngine over time")
struct FocusEngineTimeTests {
    var clock = FakeClock()

    func start(_ mode: SessionMode = .normal, minutes: Double = 25) throws -> FocusSession {
        let request = SessionRequest(id: UUID(), taskID: 7, action: "Outline the essay", mode: mode, duration: minutes * 60)
        return try #require(FocusEngine.handle(.start(request), session: nil, at: clock.now).session)
    }

    @Test mutating func reconcilingBeforeAnyDeadlineOnlyRepublishesThePolicy() throws {
        let running = try start()
        clock.advance(minutes: 10)

        let transition = try FocusEngine.handle(.reconcile, session: running, at: clock.now)

        #expect(transition.session == running)
        #expect(transition.effects == [
            .publishPolicy(SessionPolicy(sessionID: running.id, mode: .normal, end: running.plannedEnd)),
        ])
    }

    @Test mutating func reachingThePlannedEndEndsTheSessionAndNotifies() throws {
        let running = try start(minutes: 25)
        clock.advance(minutes: 25)

        let transition = try FocusEngine.handle(.reconcile, session: running, at: clock.now)

        let ended = try #require(transition.session)
        #expect(ended.phase == .ended(at: running.plannedEnd, reason: .reachedPlannedEnd))
        #expect(transition.effects == [.persist(ended), .publishPolicy(nil), .notify(.sessionReachedPlannedEnd)])
    }

    @Test(arguments: [SessionMode.normal, .strict])
    mutating func sleepingAcrossThePlannedEndRecordsTheEndAtThePlannedInstant(mode: SessionMode) throws {
        let running = try start(mode, minutes: 25)
        clock.advance(minutes: 10)
        // The Mac sleeps here and wakes three hours later.
        clock.advance(minutes: 180)

        let transition = try FocusEngine.handle(.reconcile, session: running, at: clock.now)

        let ended = try #require(transition.session)
        #expect(ended.phase == .ended(at: running.plannedEnd, reason: .reachedPlannedEnd))
        // For a strict session this is the app confirming the end the extensions waited for.
        #expect(transition.effects == [.persist(ended), .publishPolicy(nil), .notify(.sessionReachedPlannedEnd)])
    }
}
