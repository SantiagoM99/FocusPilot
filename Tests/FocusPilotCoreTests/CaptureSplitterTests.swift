import Foundation
import Testing
@testable import FocusPilotCore

/// Stands in for a system spelling checker that has only the English
/// dictionary. It is case-sensitive, like the real one for names.
let englishOnly: Set<String> = ["match", "money", "monkey", "fridge", "banana", "total", "lunch", "sundae", "Martha"]

@Suite("CaptureSplitter")
struct CaptureSplitterTests {
    private func split(_ text: String) -> CaptureSplit {
        CaptureSplitter(parser: DeadlineParser(now: wednesdayMorningInBogota, timeZone: bogota))
            .split(text, isKnownWord: englishOnly.contains)
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
        // An ordinary word close to a date name stays in the title.
        ("Fix the match by Friday", "Fix the match", "by Friday"),
        ("Clean the fridge by Friday", "Clean the fridge", "by Friday"),
        ("Pay money by Friday", "Pay money", "by Friday"),
        ("Update total by 5pm", "Update total", "by 5pm"),
        // A time written as one token counts without a marker.
        ("Meet Ana 10:00", "Meet Ana", "10:00"),
        ("Watch the match 10:00", "Watch the match", "10:00"),
        ("Buy banana 3pm", "Buy banana", "3pm"),
        ("Pay money 5pm", "Pay money", "5pm"),
        ("Feed the monkey 8am", "Feed the monkey", "8am"),
        ("Clean the fridge 9am", "Clean the fridge", "9am"),
        ("Comprar el marco 10:00", "Comprar el marco", "10:00"),
        ("Meet at lunch 12pm", "Meet at lunch", "12pm"),
        // A bare time opens the phrase when a date word follows it.
        ("Submit 12 pm Friday", "Submit", "12 pm Friday"),
        // Spanish weekdays and months after el, para or antes del.
        ("Llamar a Ana el viernes", "Llamar a Ana", "el viernes"),
        ("Entregar informe para el 20 de octubre", "Entregar informe", "para el 20 de octubre"),
        ("Pagar arriendo antes del lunes 9:00", "Pagar arriendo", "antes del lunes 9:00"),
    ])
    func onlyTheReadableTrailingPhraseBecomesTheDeadline(text: String, title: String, deadlineText: String) {
        let result = split(text)

        #expect(result.title == title)
        #expect(result.deadlineText == deadlineText)
        #expect(result.deadline != nil)
    }

    @Test func timeBeforeTheDateIsKept() {
        let result = split("Submit 12pm Friday")

        #expect(result.title == "Submit")
        #expect(result.deadlineText == "12pm Friday")
        #expect(result.deadline?.due == .timed(instant("2026-10-16T12:00:00-05:00")))
    }

    @Test(arguments: [
        "Email Ana", "Read paper by Smith", "Work on parser", "Work on 3 chapters", "tomorrow", "Plan 2027",
        // Abbreviations and "N pm" count only after a marker word.
        "Read The Sun", "Ir al mar 3", "Call Jan 3", "Read page 3 pm", "Read chapter 12 pm",
        "Submit PhD shortlist Oct 20", "Pin 2-3-4",
        // A marker followed by ordinary words is part of the title.
        "Go running on Sundays", "Write report on today's meeting", "Read article on May Day", "Comment on 3rd draft",
        // Ordinary words close to a date name are not misspellings.
        "Compute total", "Watch the match", "Buy banana", "Feed the monkey", "Buy Sundae",
        "Meet at lunch", "Comment on match", "Comprar el marco", "Jugar el domino",
        // Spanish names need a marker: "Domingo" is also a name.
        "Llamar a Domingo", "Entregar informe viernes",
    ])
    func textWithoutADeadlinePhraseIsAllTitle(_ text: String) {
        let result = split(text)

        #expect(result.title == text)
        #expect(result.deadlineText == nil)
        #expect(result.deadline == nil)
    }

    @Test func bareTimeIsTodayAtThatTime() {
        let result = split("Watch the match 10:00")

        #expect(result.deadline?.due == .timed(instant("2026-10-14T10:00:00-05:00")))
        #expect(result.unrecognizedWord == nil)
    }

    // Only a clear date with impossible values after a marker blocks saving.
    @Test(arguments: [
        ("Write report by Oct 32", "Write report", "by Oct 32"),
        ("Pay rent by Feb 30", "Pay rent", "by Feb 30"),
        ("Entregar informe para el 31 de febrero", "Entregar informe", "para el 31 de febrero"),
        ("Call Ana at 25:00", "Call Ana", "at 25:00"),
        ("Call Ana at 13pm", "Call Ana", "at 13pm"),
        ("Finish draft due 12am", "Finish draft", "due 12am"),
    ])
    func phraseThatLooksLikeADeadlineButCannotBeReadIsKeptAsUnreadable(text: String, title: String, deadlineText: String) {
        let result = split(text)

        #expect(result.title == title)
        #expect(result.deadlineText == deadlineText)
        #expect(result.deadline == nil)
    }

    // A guessed misspelling never blocks saving and never takes words out
    // of the title; it only names the word for a quiet hint.
    @Test(arguments: [
        ("Present fryday", "fryday"),
        ("Send slides by next tuesdy", "tuesdy"),
        ("Llamar a Ana mañnana", "mañnana"),
        ("Llamar a Ana el vierns", "vierns"),
    ])
    func nearMissDateWordKeepsTheWholeTitleAndIsNamed(text: String, word: String) {
        let result = split(text)

        #expect(result.title == text)
        #expect(result.deadlineText == nil)
        #expect(result.deadline == nil)
        #expect(result.unrecognizedWord == word)
    }

    // A guessed typo never drops a readable deadline; it stays in the title.
    @Test(arguments: [
        ("Call Martha by Friday", "Call Martha", "by Friday"),
        ("Email Marta by Friday", "Email Marta", "by Friday"),
        ("Llamar a Marco el viernes", "Llamar a Marco", "el viernes"),
        ("Present fryday by 10:00", "Present fryday", "by 10:00"),
        ("Present fryday 10:00", "Present fryday", "10:00"),
        ("Llamar a Ana mañnana 10:00", "Llamar a Ana mañnana", "10:00"),
    ])
    func readableDeadlineWinsOverANearMissWord(text: String, title: String, deadlineText: String) {
        let result = split(text)

        #expect(result.title == title)
        #expect(result.deadlineText == deadlineText)
        #expect(result.deadline != nil)
        #expect(result.unrecognizedWord == nil)
    }

    // Real words and names, from the bundled list, the checker, or a capital
    // letter mid-sentence, even without a Spanish dictionary.
    @Test(arguments: [
        "Watch the match", "Buy Sundae", "Feed the monkey 8am", "Comprar el marco", "Comprar el marco 10:00",
        "Jugar el domino", "Call Ana", "Call Marta", "Ver a Mario", "Hablar con Domingo", "Comprar todas",
        "Comprar huevos", "Llamar a Maria", "Email Fryda",
    ])
    func realWordsAreNotNamedAsMisspellings(_ text: String) {
        #expect(split(text).unrecognizedWord == nil)
    }

    @Test func impossibleDateAloneStillBlocks() {
        let result = split("by Feb 30")

        #expect(result.title == "")
        #expect(result.deadlineText == "by Feb 30")
        #expect(result.deadline == nil)
    }
}

@Suite("CaptureDraft")
struct CaptureDraftTests {
    private func draft(_ text: String, now: Date = wednesdayMorningInBogota) -> CaptureDraft {
        var draft = CaptureDraft()
        draft.setText(text, now: now, timeZone: bogota, isKnownWord: englishOnly.contains)
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

    @Test func nearMissDateWordShowsAHintButSaves() {
        let typed = draft("Present fryday")

        #expect(typed.unrecognizedDateHint == "Did you mean a date? “fryday” wasn’t recognized.")
        #expect(typed.newTask == NewTask(title: "Present fryday"))
        #expect(draft("Present Friday 10:00").unrecognizedDateHint == nil)
    }

    @Test func impossibleDateTypedAloneCannotBeSaved() {
        #expect(draft("by Feb 30").isDeadlineUnreadable)
        #expect(draft("by Feb 30").newTask == nil)
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

        typed.setText("Read paper by Oct 21", now: wednesdayMorningInBogota, timeZone: bogota, isKnownWord: englishOnly.contains)

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
