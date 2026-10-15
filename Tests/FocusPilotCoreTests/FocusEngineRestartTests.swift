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

/// Fixed JSON for persisted sessions: renaming a case, label or property must
/// fail here rather than silently break restoring sessions saved earlier.
@Suite("FocusSession golden JSON")
struct FocusSessionGoldenJSONTests {
    func decode(phase: String) throws -> FocusSession {
        let json = """
        {"id":"0B7A3C2E-5D41-4F6A-9E8B-1C2D3E4F5A6B","taskID":7,"action":"Outline the essay",
         "mode":"strict","startedAt":800000000,"plannedEnd":800001500,"phase":\(phase)}
        """
        return try JSONDecoder().decode(FocusSession.self, from: Data(json.utf8))
    }

    func instant(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    @Test func decodesTheSessionFields() throws {
        let session = try decode(phase: #"{"kind":"running"}"#)

        #expect(session == FocusSession(
            id: UUID(uuidString: "0B7A3C2E-5D41-4F6A-9E8B-1C2D3E4F5A6B")!, taskID: 7, action: "Outline the essay",
            mode: .strict, startedAt: instant(800_000_000), plannedEnd: instant(800_001_500), phase: .running
        ))
    }

    @Test func decodesEveryPhase() throws {
        #expect(try decode(phase: #"{"kind":"paused","since":800000600}"#).phase == .paused(since: instant(800_000_600)))
        #expect(try decode(phase: #"{"kind":"onBreak","until":800000900}"#).phase == .onBreak(until: instant(800_000_900)))
        #expect(try decode(phase: #"{"kind":"ended","at":800001500,"reason":"reachedPlannedEnd"}"#).phase
            == .ended(at: instant(800_001_500), reason: .reachedPlannedEnd))
        #expect(try decode(phase: #"{"kind":"ended","at":800001200,"reason":"completed"}"#).phase
            == .ended(at: instant(800_001_200), reason: .completed))
    }

    @Test func normalModeIsStoredByName() throws {
        let json = try JSONEncoder().encode(SessionMode.normal)

        #expect(String(decoding: json, as: UTF8.self) == #""normal""#)
    }
}
