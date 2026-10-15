import Foundation
import Testing
@testable import FocusPilotCore

@Suite("CaptureSplitter")
struct CaptureSplitterTests {
    private func split(_ text: String) -> CaptureSplit {
        CaptureSplitter(parser: DeadlineParser(now: wednesdayMorningInBogota, timeZone: bogota)).split(text)
    }

    @Test func trailingDeadlinePhraseIsSplitOffTheTitle() {
        let result = split("Write NLP report by Friday 11pm")

        #expect(result.title == "Write NLP report")
        #expect(result.deadlineText == "by Friday 11pm")
        #expect(result.deadline?.due == .timed(instant("2026-10-16T23:00:00-05:00")))
        #expect(result.deadline?.originalText == "by Friday 11pm")
    }

    @Test(arguments: [
        ("Read paper by Smith by Oct 20", "Read paper by Smith", "by Oct 20"),
        ("Prepare 2026 budget by fri", "Prepare 2026 budget", "by fri"),
        ("Submit PhD shortlist October 20", "Submit PhD shortlist", "October 20"),
        ("Buy milk tomorrow", "Buy milk", "tomorrow"),
        ("Plan trip 2026-11-02", "Plan trip", "2026-11-02"),
        ("Llamar a Ana mañana 10:00", "Llamar a Ana", "mañana 10:00"),
        ("Entregar informe para pasado mañana", "Entregar informe", "para pasado mañana"),
        ("Revisar notas hoy 18:00", "Revisar notas", "hoy 18:00"),
        ("Meet Ana at 3 pm", "Meet Ana", "at 3 pm"),
        ("Reschedule March by Friday", "Reschedule March", "by Friday"),
        ("Hand in essay due next mon 9:00", "Hand in essay", "due next mon 9:00"),
        ("Renew library access before 2026-10-31", "Renew library access", "before 2026-10-31"),
        ("Call bank, by tomorrow", "Call bank", "by tomorrow"),
    ])
    func onlyTheReadableTrailingPhraseBecomesTheDeadline(text: String, title: String, deadlineText: String) {
        let result = split(text)

        #expect(result.title == title)
        #expect(result.deadlineText == deadlineText)
        #expect(result.deadline != nil)
    }

    @Test(arguments: [
        "Email Ana", "Read paper by Smith", "Work on parser", "Work on 3 chapters", "tomorrow", "Plan 2027",
        // Abbreviations and "N pm" count only after a marker word.
        "Read The Sun", "Ir al mar 3", "Call Jan 3", "Read page 3 pm", "Read chapter 12 pm",
        "Submit PhD shortlist Oct 20", "Meet Ana 10:00", "Pin 2-3-4",
        // A marker followed by ordinary words is part of the title.
        "Go running on Sundays", "Write report on today's meeting", "Read article on May Day", "Comment on 3rd draft",
    ])
    func textWithoutADeadlinePhraseIsAllTitle(_ text: String) {
        let result = split(text)

        #expect(result.title == text)
        #expect(result.deadlineText == nil)
        #expect(result.deadline == nil)
    }

    @Test(arguments: [
        ("Write report by Oct 32", "Write report", "by Oct 32"),
        ("Finish draft due 12am", "Finish draft", "due 12am"),
        ("Send slides by next tuesdy", "Send slides", "by next tuesdy"),
        ("Present on fryday 10:00", "Present", "on fryday 10:00"),
        ("Llamar a Ana mañnana 10:00", "Llamar a Ana", "mañnana 10:00"),
        ("Present fryday by 10:00", "Present", "fryday by 10:00"),
    ])
    func phraseThatLooksLikeADeadlineButCannotBeReadIsKeptAsUnreadable(text: String, title: String, deadlineText: String) {
        let result = split(text)

        #expect(result.title == title)
        #expect(result.deadlineText == deadlineText)
        #expect(result.deadline == nil)
    }
}

@Suite("CaptureDraft")
struct CaptureDraftTests {
    private func draft(_ text: String, now: Date = wednesdayMorningInBogota) -> CaptureDraft {
        var draft = CaptureDraft()
        draft.setText(text, now: now, timeZone: bogota)
        return draft
    }

    @Test func savesExactlyTheDeadlineThatWasPreviewed() {
        // Typed a few seconds before midnight: "tomorrow" was previewed as
        // Thursday, and saving after midnight must not turn it into Friday.
        let typed = draft("Call mum by tomorrow", now: instant("2026-10-14T23:59:50-05:00"))

        #expect(typed.deadline?.due == .dateOnly(LocalDate(year: 2026, month: 10, day: 15)))
        #expect(typed.newTask?.deadline == typed.deadline)
        #expect(typed.newTask?.title == "Call mum")
    }

    @Test func titleOnlyCaptureNeedsNoDeadline() {
        #expect(draft("Email Ana").newTask == NewTask(title: "Email Ana"))
    }

    @Test func blankTextCannotBeSaved() {
        #expect(draft("   ").newTask == nil)
    }

    @Test func unreadableDeadlineBlocksSavingUntilRemoved() {
        var typed = draft("Write report by Oct 32")
        #expect(typed.isDeadlineUnreadable)
        #expect(typed.newTask == nil)

        typed.removeDeadline()

        #expect(!typed.isDeadlineUnreadable)
        #expect(typed.newTask == NewTask(title: "Write report by Oct 32"))
    }

    @Test func removingAReadableDeadlinePutsThePhraseBackInTheTitle() {
        var typed = draft("Meet Ana at noon")

        typed.removeDeadline()

        #expect(typed.title == "Meet Ana at noon")
        #expect(typed.newTask?.deadline == nil)
    }

    @Test func ownerCanCorrectTitleAndDeadline() {
        var typed = draft("Read paper by Smith by Oct 20")

        typed.title = "Read Smith's paper"
        typed.correctDeadline(typed.deadline!.addingTime(hour: 18, minute: 0))

        #expect(typed.newTask?.title == "Read Smith's paper")
        #expect(typed.newTask?.deadline?.due == .timed(instant("2026-10-20T18:00:00-05:00")))
        #expect(typed.newTask?.deadline?.originalText == "by Oct 20")
    }

    @Test func typingAgainDiscardsCorrections() {
        var typed = draft("Read paper by Oct 20")
        typed.title = "Edited"
        typed.removeDeadline()

        typed.setText("Read paper by Oct 21", now: wednesdayMorningInBogota, timeZone: bogota)

        #expect(typed.title == "Read paper")
        #expect(typed.deadline?.due == .dateOnly(LocalDate(year: 2026, month: 10, day: 21)))
    }

    @Test func projectAndNextActionAreCarriedIntoTheTask() {
        var typed = draft("Write NLP report by fri")
        typed.projectName = "NLP report"
        typed.nextAction = "Open Overleaf"

        #expect(typed.newTask?.projectName == "NLP report")
        #expect(typed.newTask?.nextAction == "Open Overleaf")
    }
}
