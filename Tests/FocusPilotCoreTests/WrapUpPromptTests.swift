import Foundation
import Testing
@testable import FocusPilotCore

@Suite("When the wrap-up sheet appears")
struct WrapUpPromptTests {
    private let start = wednesdayMorningInBogota

    private func session(_ phase: SessionPhase, id: UUID = UUID(uuidString: "0B7A3C2E-5D41-4F6A-9E8B-1C2D3E4F5A6B")!) -> FocusSession {
        FocusSession(id: id, taskID: 7, action: "Explain baseline results", mode: .normal,
                     startedAt: start, plannedEnd: start.addingTimeInterval(50 * 60), phase: phase)
    }

    private func minutes(_ minutes: Double) -> Date {
        start.addingTimeInterval(minutes * 60)
    }

    @Test func pausingARunningSessionAsksForAWrapUp() {
        let prompt = WrapUpPrompt.after(session(.running), session(.paused(since: minutes(20))))

        #expect(prompt == WrapUpPrompt(session: session(.paused(since: minutes(20))), moment: .paused))
        #expect(prompt?.title == "Session paused")
        #expect(prompt?.detail == "Explain baseline results · 20 min")
    }

    @Test(arguments: [EndReason.completed, .reachedPlannedEnd])
    func endingASessionAsksForAWrapUp(reason: EndReason) {
        let ended = session(.ended(at: minutes(50), reason: reason))

        let prompt = WrapUpPrompt.after(session(.paused(since: minutes(30))), ended)

        #expect(prompt?.moment == .ended)
        #expect(prompt?.title == "Session ended")
        #expect(prompt?.detail == "Explain baseline results · 50 min")
    }

    @Test func otherChangesDoNotAsk() {
        let running = session(.running)
        let paused = session(.paused(since: minutes(20)))
        let ended = session(.ended(at: minutes(50), reason: .completed))

        #expect(WrapUpPrompt.after(nil, running) == nil, "starting")
        #expect(WrapUpPrompt.after(paused, running) == nil, "resuming")
        #expect(WrapUpPrompt.after(running, session(.onBreak(until: minutes(30)))) == nil, "taking a break")
        #expect(WrapUpPrompt.after(running, running) == nil, "no change")
        #expect(WrapUpPrompt.after(ended, ended) == nil, "already ended")
        #expect(WrapUpPrompt.after(nil, ended) == nil, "ended while the app was quit")
        #expect(WrapUpPrompt.after(running, session(.paused(since: minutes(20)), id: UUID())) == nil, "another session")
    }
}
