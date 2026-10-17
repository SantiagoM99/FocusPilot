import Foundation
import Testing
@testable import FocusPilotCore

@Suite("Wrap-up draft")
struct WrapUpDraftTests {
    @Test func startsFromWhatTheTaskAlreadySaysSoSavingTakesSeconds() {
        let earlier = TaskWrapUp(WrapUp(outcome: "Drafted §4.2", remainingWork: "Ablation sentence", returnCue: "Check Table 3"),
                                 session: UUID(), at: wednesdayMorningInBogota)
        let task = TodayItem(id: 1, title: "Explain baseline results", nextAction: "Write one sentence under Table 3",
                             wrapUp: earlier)

        let draft = WrapUpDraft(task: task)

        #expect(draft.outcome == "")
        #expect(draft.remainingWork == "Ablation sentence")
        #expect(draft.returnCue == "Write one sentence under Table 3")
    }

    @Test func aTaskWithNothingSavedStartsEmpty() {
        let draft = WrapUpDraft(task: TodayItem(id: 1, title: "Explain baseline results"))

        #expect(draft == WrapUpDraft())
    }

    @Test func savesTrimmedTextAndBlankFieldsAsNothing() {
        let draft = WrapUpDraft(outcome: "  Drafted §4.2\n", remainingWork: " \n ", returnCue: "Check Table 3 ")

        #expect(draft.wrapUp == WrapUp(outcome: "Drafted §4.2", remainingWork: nil, returnCue: "Check Table 3"))
    }
}
