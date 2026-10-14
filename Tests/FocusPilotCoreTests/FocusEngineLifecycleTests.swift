import Foundation
import Testing
@testable import FocusPilotCore

@Suite("FocusEngine lifecycle")
struct FocusEngineLifecycleTests {
    var clock = FakeClock()
    let sessionID = UUID()

    func startRequest(mode: SessionMode = .normal, minutes: Double = 25) -> SessionRequest {
        SessionRequest(id: sessionID, taskID: 7, action: "Outline the essay", mode: mode, duration: minutes * 60)
    }

    @Test func startingRunsASessionUntilAnAbsolutePlannedEnd() throws {
        let transition = try FocusEngine.handle(.start(startRequest(minutes: 25)), session: nil, at: clock.now)

        let expected = FocusSession(
            id: sessionID, taskID: 7, action: "Outline the essay", mode: .normal,
            startedAt: clock.now, plannedEnd: clock.minutes(from: clock.now, 25), phase: .running
        )
        #expect(transition.session == expected)
        #expect(transition.effects == [
            .persist(expected),
            .publishPolicy(SessionPolicy(sessionID: sessionID, mode: .normal, end: expected.plannedEnd)),
        ])
    }
}
