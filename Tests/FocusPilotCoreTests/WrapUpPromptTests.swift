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

    @Test(arguments: [EndReason.completed, .reachedPlannedEnd])
    func endingASessionAsksForAWrapUp(reason: EndReason) {
        let ended = session(.ended(at: minutes(50), reason: reason))

        let prompt = WrapUpPrompt.after(session(.paused(since: minutes(30))), ended)

        #expect(prompt == WrapUpPrompt(session: ended))
        #expect(prompt?.title == "Session ended")
        #expect(prompt?.detail == "Explain baseline results · 50 min")
    }

    /// Owner decision, 2026-10-17: no wrap-up on pause.
    @Test func otherChangesDoNotAsk() {
        let running = session(.running)
        let paused = session(.paused(since: minutes(20)))
        let ended = session(.ended(at: minutes(50), reason: .completed))

        #expect(WrapUpPrompt.after(running, paused) == nil, "pausing")
        #expect(WrapUpPrompt.after(nil, running) == nil, "starting")
        #expect(WrapUpPrompt.after(paused, running) == nil, "resuming")
        #expect(WrapUpPrompt.after(running, session(.onBreak(until: minutes(30)))) == nil, "taking a break")
        #expect(WrapUpPrompt.after(running, running) == nil, "no change")
        #expect(WrapUpPrompt.after(ended, ended) == nil, "already ended")
        #expect(WrapUpPrompt.after(nil, ended) == nil, "ended while the app was quit")
        #expect(WrapUpPrompt.after(running, session(.ended(at: minutes(50), reason: .completed), id: UUID())) == nil,
                "another session")
    }

    @Test func aPromptIsIdentifiedByItsSession() {
        let ended = session(.ended(at: minutes(50), reason: .completed))

        #expect(WrapUpPrompt(session: ended).id == ended.id)
    }
}

@Suite("Pending wrap-up")
struct PendingWrapUpTests {
    private let task = TodayItem(id: 7, title: "Explain baseline results", nextAction: "Check Table 3")

    private func prompt(_ id: UUID) -> WrapUpPrompt {
        let start = wednesdayMorningInBogota
        return WrapUpPrompt(session: FocusSession(id: id, taskID: 7, action: "Explain baseline results", mode: .normal,
                                                  startedAt: start, plannedEnd: start.addingTimeInterval(3000),
                                                  phase: .ended(at: start.addingTimeInterval(3000), reason: .completed)))
    }

    @Test func aNewPromptStartsFromTheTask() {
        let pending = PendingWrapUp.receiving(prompt(UUID()), replacing: nil, task: task)

        #expect(pending.draft == WrapUpDraft(task: task))
    }

    @Test func theSameSessionAgainKeepsWhatTheOwnerTyped() {
        let id = UUID()
        var typing = PendingWrapUp.receiving(prompt(id), replacing: nil, task: task)
        typing.draft.outcome = "Drafted §4.2"
        typing.draft.marksTaskDone = true

        let again = PendingWrapUp.receiving(prompt(id), replacing: typing, task: task)

        #expect(again.draft.outcome == "Drafted §4.2")
        #expect(again.draft.marksTaskDone)
    }

    @Test func anotherSessionStartsFresh() {
        var typing = PendingWrapUp.receiving(prompt(UUID()), replacing: nil, task: task)
        typing.draft.outcome = "Drafted §4.2"
        typing.draft.marksTaskDone = true

        let next = PendingWrapUp.receiving(prompt(UUID()), replacing: typing, task: task)

        #expect(next.draft.outcome == "")
        #expect(!next.draft.marksTaskDone)
    }
}
