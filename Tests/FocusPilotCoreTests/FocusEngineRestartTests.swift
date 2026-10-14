import Foundation
import Testing
@testable import FocusPilotCore

@Suite("FocusEngine restart")
struct FocusEngineRestartTests {
    var clock = FakeClock()

    /// Starts a session and returns what the coordinator was asked to persist,
    /// encoded and decoded as storage would.
    func persistedSession(_ mode: SessionMode, minutes: Double) throws -> FocusSession {
        let request = SessionRequest(id: UUID(), taskID: 7, action: "Outline the essay", mode: mode, duration: minutes * 60)
        let effects = try FocusEngine.handle(.start(request), session: nil, at: clock.now).effects
        guard case .persist(let session) = effects.first else {
            Issue.record("Starting a session did not persist it")
            throw CancellationError()
        }
        return try JSONDecoder().decode(FocusSession.self, from: JSONEncoder().encode(session))
    }

    @Test mutating func relaunchingMidSessionRepublishesThePolicyWithoutRewritingTheSession() throws {
        let restored = try persistedSession(.strict, minutes: 50)
        clock.advance(minutes: 15)

        let transition = try FocusEngine.handle(.reconcile, session: restored, at: clock.now)

        #expect(transition.session == restored)
        #expect(transition.effects == [
            .publishPolicy(SessionPolicy(sessionID: restored.id, mode: .strict, end: restored.plannedEnd)),
        ])
    }

    @Test mutating func relaunchingAfterAStrictSessionsEndConfirmsTheEnd() throws {
        let restored = try persistedSession(.strict, minutes: 25)
        clock.advance(minutes: 90)

        let transition = try FocusEngine.handle(.reconcile, session: restored, at: clock.now)

        let ended = try #require(transition.session)
        #expect(ended.phase == .ended(at: restored.plannedEnd, reason: .reachedPlannedEnd))
        #expect(transition.effects == [.persist(ended), .publishPolicy(nil), .notify(.sessionReachedPlannedEnd)])
    }

    @Test mutating func relaunchingAfterAnEndedSessionChangesNothing() throws {
        let restored = try persistedSession(.normal, minutes: 25)
        let ended = try FocusEngine.handle(.complete, session: restored, at: clock.now).session
        clock.advance(minutes: 600)

        let transition = try FocusEngine.handle(.reconcile, session: ended, at: clock.now)

        #expect(transition.session == ended)
        #expect(transition.effects == [.publishPolicy(nil)])
    }

    @Test func launchingWithNoSessionPublishesNoSessionRules() throws {
        let transition = try FocusEngine.handle(.reconcile, session: nil, at: clock.now)

        #expect(transition.session == nil)
        #expect(transition.effects == [.publishPolicy(nil)])
    }
}
