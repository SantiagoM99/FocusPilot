import Foundation
import Testing
@testable import FocusPilotCore

/// The planning window shows one sheet at a time; these pin which one wins
/// when several are wanted, so none is silently lost.
@Suite("Planning window sheet")
struct PlanningSheetTests {
    private let wrapUp: PendingWrapUp = {
        let start = wednesdayMorningInBogota
        let session = FocusSession(id: UUID(), taskID: 7, action: "Explain baseline results", mode: .normal,
                                   startedAt: start, plannedEnd: start.addingTimeInterval(3000),
                                   phase: .ended(at: start.addingTimeInterval(3000), reason: .completed))
        return PendingWrapUp(prompt: WrapUpPrompt(session: session), draft: WrapUpDraft())
    }()

    @Test func nothingWantedShowsNothing() {
        #expect(PlanningSheet.showing(isCapturing: false, wrapUp: nil, isStartingFocus: false) == nil)
    }

    @Test func aWaitingWrapUpComesBeforeStartFocus() {
        #expect(PlanningSheet.showing(isCapturing: false, wrapUp: wrapUp, isStartingFocus: true) == .wrapUp(wrapUp.id))
    }

    @Test func startFocusFollowsOnceTheWrapUpIsSavedOrSkipped() {
        #expect(PlanningSheet.showing(isCapturing: false, wrapUp: nil, isStartingFocus: true) == .startFocus)
    }

    @Test func captureTheOwnerIsTypingInStaysOnTopAndTheWrapUpWaits() {
        #expect(PlanningSheet.showing(isCapturing: true, wrapUp: wrapUp, isStartingFocus: true) == .capture)
    }

    // #57: Switch and Mark as waiting are the owner's clicks; a wrap-up already waiting goes first.
    @Test func switchAndMarkAsWaitingComeAfterAWrapUpAndBeforeStartFocus() {
        let request = SwitchRequest(taskID: 4, taskTitle: "Run ablation", linkID: 2, agentLabel: "ablation", item: nil)

        #expect(PlanningSheet.showing(isCapturing: false, wrapUp: wrapUp, isStartingFocus: false, switching: request)
            == .wrapUp(wrapUp.id))
        #expect(PlanningSheet.showing(isCapturing: false, wrapUp: nil, isStartingFocus: true, switching: request,
                                      markingWaiting: 9) == .switchTask(request.id))
        #expect(PlanningSheet.showing(isCapturing: false, wrapUp: nil, isStartingFocus: true, markingWaiting: 9)
            == .markWaiting(9))
    }
}
