import Foundation
import Testing
@testable import FocusPilotCore

/// Stands in for a system spelling checker that has only the English
/// dictionary. It is case-sensitive, like the real one for names.
let englishOnly: Set<String> = ["match", "money", "monkey", "fridge", "banana", "total", "lunch", "sundae", "Martha", "Marcia"]

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
        ("Call Fryday by Friday", "Call Fryday", "by Friday"),
    ])
    func readableDeadlineWinsOverANearMissWord(text: String, title: String, deadlineText: String) {
        let result = split(text)

        #expect(result.title == title)
        #expect(result.deadlineText == deadlineText)
        #expect(result.deadline != nil)
        #expect(result.unrecognizedWord == nil)
    }

    // #31: a time alone means today, so a typo just before it is probably
    // the day the owner meant. The time still wins; the typo gets the hint.
    @Test(arguments: [
        ("Submit report fryday 5pm", "Submit report fryday", "5pm", "fryday"),
        ("Present fryday by 10:00", "Present fryday", "by 10:00", "fryday"),
        ("Present fryday 10:00", "Present fryday", "10:00", "fryday"),
        ("Llamar a Ana mañnana 10:00", "Llamar a Ana mañnana", "10:00", "mañnana"),
        ("Present Fryday at 3 pm", "Present Fryday", "at 3 pm", "Fryday"),
    ])
    func aTypoBeforeATimeKeepsTheTimeAndIsNamed(text: String, title: String, deadlineText: String, word: String) {
        let result = split(text)

        #expect(result.title == title)
        #expect(result.deadlineText == deadlineText)
        #expect(result.deadline?.due == DeadlineParser(now: wednesdayMorningInBogota, timeZone: bogota).parse(deadlineText)?.due)
        #expect(result.unrecognizedWord == word)
    }

    @Test func aTypoBeforeATimeStillMeansToday() {
        #expect(split("Submit report fryday 5pm").deadline?.due == .timed(instant("2026-10-14T17:00:00-05:00")))
    }

    // #31: capitalized and all-caps typos are named; real names, from the
    // bundled list or the checker in any case, are not.
    @Test(arguments: [
        ("Present Fryday", "Fryday"),
        ("PRESENT FRYDAY", "FRYDAY"),
        ("Send slides by next Tuesdy", "Tuesdy"),
        ("LLAMAR A ANA EL VIERNS", "VIERNS"),
    ])
    func capitalizedTyposAreNamed(text: String, word: String) {
        let result = split(text)

        #expect(result.title == text)
        #expect(result.deadline == nil)
        #expect(result.unrecognizedWord == word)
    }

    @Test(arguments: [
        "Call Martha", "CALL MARTHA", "Call Marcia", "CALL MARCIA", "Email Fryda", "EMAIL FRYDA",
        "Watch the Match", "WATCH THE MATCH", "Llamar a Marco", "HABLAR CON DOMINGO", "Ver a Mario",
    ])
    func capitalizedRealNamesAndWordsAreNotNamed(_ text: String) {
        #expect(split(text).unrecognizedWord == nil)
    }

    // #31: sentence punctuation after the deadline does not hide it.
    @Test(arguments: [
        ("Buy milk, tomorrow.", "Buy milk", "tomorrow"),
        ("Buy milk tomorrow!", "Buy milk", "tomorrow"),
        ("Write NLP report by Friday 11pm.", "Write NLP report", "by Friday 11pm"),
        ("Llamar a Ana mañana 10:00.", "Llamar a Ana", "mañana 10:00"),
        ("Entregar informe el viernes?", "Entregar informe", "el viernes"),
        ("Meet Ana 10:00...", "Meet Ana", "10:00"),
    ])
    func trailingPunctuationIsNotPartOfTheDeadline(text: String, title: String, deadlineText: String) {
        let result = split(text)

        #expect(result.title == title)
        #expect(result.deadlineText == deadlineText)
        #expect(result.deadline != nil)
        #expect(result.deadline?.due == DeadlineParser(now: wednesdayMorningInBogota, timeZone: bogota).parse(deadlineText)?.due)
        #expect(result.deadline?.originalText == deadlineText)
    }

    @Test func anImpossibleDateWithAFullStopStillBlocks() {
        let result = split("Pay rent by Feb 30.")

        #expect(result.title == "Pay rent")
        #expect(result.deadlineText == "by Feb 30")
        #expect(result.deadline == nil)
    }

    @Test(arguments: ["Email Ana.", "Read page 3 pm.", "Go running on Sundays."])
    func aTitleWithAFullStopAndNoDeadlineIsKeptAsTyped(_ text: String) {
        let result = split(text)

        #expect(result.title == text)
        #expect(result.deadlineText == nil)
    }

    @Test func aTypoWithAFullStopIsNamedWithoutIt() {
        #expect(split("Present fryday.").unrecognizedWord == "fryday")
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

    // #31: the hint shows next to the time, and saving keeps the time.
    @Test func aTypoBeforeATimeShowsAHintAndSavesTheTime() {
        let typed = draft("Submit report fryday 5pm")

        #expect(typed.unrecognizedDateHint == "Did you mean a date? “fryday” wasn’t recognized.")
        #expect(typed.newTask?.title == "Submit report fryday")
        #expect(typed.newTask?.deadline?.due == .timed(instant("2026-10-14T17:00:00-05:00")))
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

    // Owner feedback: a deadline can also be chosen by hand.
    @Test func openingThePickerProposesTodayWithoutCommittingIt() {
        let typed = draft("Entregar informe")

        let proposal = typed.proposedDeadline(now: wednesdayMorningInBogota, timeZone: bogota)

        #expect(proposal.due == .dateOnly(LocalDate(year: 2026, month: 10, day: 14)))
        #expect(proposal.timeZone == bogota)
        #expect(proposal.isChosenByHand)
        #expect(typed.deadline == nil)
        #expect(typed.newTask == NewTask(title: "Entregar informe"))
    }

    @Test func thePickerProposesTheCurrentDeadlineWhenThereIsOne() {
        let typed = draft("Entregar informe el viernes 5pm")

        #expect(typed.proposedDeadline(now: wednesdayMorningInBogota, timeZone: bogota) == typed.deadline)
    }

    @Test func aPickIsCommittedOnlyWhenChosen() {
        var typed = draft("Entregar informe")
        let proposal = typed.proposedDeadline(now: wednesdayMorningInBogota, timeZone: bogota)

        typed.correctDeadline(proposal.moving(to: LocalDate(year: 2026, month: 10, day: 16)).addingTime(hour: 17, minute: 0))

        #expect(typed.newTask?.deadline?.due == .timed(instant("2026-10-16T17:00:00-05:00")))
        #expect(typed.title == "Entregar informe")
    }

    @Test func aHandPickOverridesAnUnreadablePhrase() {
        var typed = draft("Write report by Oct 32")
        #expect(typed.newTask == nil)

        typed.correctDeadline(typed.proposedDeadline(now: wednesdayMorningInBogota, timeZone: bogota))

        #expect(!typed.isDeadlineUnreadable)
        #expect(typed.newTask?.title == "Write report")
        #expect(typed.newTask?.deadline?.isChosenByHand == true)
    }

    @Test func aHandPickAfterRemovingKeepsTheWholeTextAsTitle() {
        var typed = draft("Meet Ana at noon")
        typed.removeDeadline()

        typed.correctDeadline(typed.proposedDeadline(now: wednesdayMorningInBogota, timeZone: bogota))

        #expect(typed.title == "Meet Ana at noon")
        #expect(typed.deadline?.isChosenByHand == true)
    }

    @Test func removeDeadlineAlsoClearsAHandPick() {
        var typed = draft("Entregar informe")
        typed.correctDeadline(typed.proposedDeadline(now: wednesdayMorningInBogota, timeZone: bogota))

        typed.removeDeadline()

        #expect(typed.newTask == NewTask(title: "Entregar informe"))
    }

    @Test func typingKeepsAHandPickWhenTheNewTextHasNoReadableDeadline() {
        var typed = draft("Entregar")
        let picked = Deadline.chosenByHand(LocalDate(year: 2026, month: 10, day: 20), timeZone: bogota)
        typed.correctDeadline(picked)

        typed.setText("Entregar informe", now: wednesdayMorningInBogota, timeZone: bogota, isKnownWord: englishOnly.contains)

        #expect(typed.deadline == picked)
        #expect(typed.newTask?.title == "Entregar informe")
    }

    @Test func typingAReadableDeadlineReplacesAHandPick() {
        var typed = draft("Entregar informe")
        typed.correctDeadline(Deadline.chosenByHand(LocalDate(year: 2026, month: 10, day: 20), timeZone: bogota))

        typed.setText("Entregar informe el viernes 5pm", now: wednesdayMorningInBogota, timeZone: bogota,
                      isKnownWord: englishOnly.contains)

        #expect(typed.deadline?.due == .timed(instant("2026-10-16T17:00:00-05:00")))
        #expect(typed.deadline?.isChosenByHand == false)
    }

    @Test func aCorrectedPhraseKeptAfterTheTextChangesCountsAsChosenByHand() {
        var typed = draft("Read paper by Oct 20")
        typed.correctDeadline(typed.deadline!.addingTime(hour: 18, minute: 0))

        typed.setText("Read paper", now: wednesdayMorningInBogota, timeZone: bogota, isKnownWord: englishOnly.contains)

        #expect(typed.deadline?.due == .timed(instant("2026-10-20T18:00:00-05:00")))
        #expect(typed.deadline?.isChosenByHand == true)
    }

    /// Types `suffix` after the current text one keystroke at a time, as the
    /// text field reports it.
    private func type(_ suffix: String, into typed: inout CaptureDraft) {
        for character in suffix {
            typed.setText(typed.text + String(character), now: wednesdayMorningInBogota, timeZone: bogota,
                          isKnownWord: englishOnly.contains)
        }
    }

    // PR #33 review: a phrase that is only readable halfway through typing
    // must not delete the hand pick for good.
    @Test func aHandPickSurvivesAPhraseThatAppearsOnlyWhileTyping() {
        var typed = draft("Call")
        let picked = Deadline.chosenByHand(LocalDate(year: 2026, month: 10, day: 20), timeZone: bogota)
        typed.correctDeadline(picked)

        type(" Ana at 10am", into: &typed)
        #expect(typed.deadline?.isChosenByHand == false)
        #expect(typed.deadlineText == "at 10am")

        type(" about the plan", into: &typed)
        #expect(typed.deadline == picked)
        #expect(typed.newTask?.title == "Call Ana at 10am about the plan")
        #expect(typed.newTask?.deadline == picked)
    }

    @Test func aHandPickReturnsWhenTheTypedPhraseIsDeletedKeystrokeByKeystroke() {
        var typed = draft("Read paper")
        let picked = Deadline.chosenByHand(LocalDate(year: 2026, month: 10, day: 20), timeZone: bogota)
        typed.correctDeadline(picked)
        type(" by Oct 21", into: &typed)
        #expect(typed.deadline?.due == .dateOnly(LocalDate(year: 2026, month: 10, day: 21)))

        while typed.text != "Read paper" {
            typed.setText(String(typed.text.dropLast()), now: wednesdayMorningInBogota, timeZone: bogota,
                          isKnownWord: englishOnly.contains)
        }

        #expect(typed.deadline == picked)
    }

    @Test func removeDeadlineClearsAHandPickHiddenByATypedPhrase() {
        var typed = draft("Read paper")
        typed.correctDeadline(Deadline.chosenByHand(LocalDate(year: 2026, month: 10, day: 20), timeZone: bogota))
        type(" by Oct 21", into: &typed)

        typed.removeDeadline()
        typed.setText("Read paper", now: wednesdayMorningInBogota, timeZone: bogota, isKnownWord: englishOnly.contains)

        #expect(typed.deadline == nil)
    }

    // PR #33 review: Done on an untouched picker must not turn a typed
    // deadline into a hand pick.
    @Test func confirmingAnUntouchedPickerKeepsTheTypedDeadlineTiedToItsPhrase() {
        var typed = draft("Read paper by Friday")
        let shown = typed.proposedDeadline(now: wednesdayMorningInBogota, timeZone: bogota)

        typed.confirmPicker(shown)
        typed.setText("Read paper", now: wednesdayMorningInBogota, timeZone: bogota, isKnownWord: englishOnly.contains)

        #expect(typed.deadline == nil)
        #expect(typed.newTask == NewTask(title: "Read paper"))
    }

    @Test func confirmingThePickerCommitsTodayWhenThereIsNoDeadline() {
        var typed = draft("Entregar informe")
        let shown = typed.proposedDeadline(now: wednesdayMorningInBogota, timeZone: bogota)

        typed.confirmPicker(shown)

        #expect(typed.deadline == shown)
    }

    @Test func confirmingAChangedPickerCommitsTheChange() {
        var typed = draft("Read paper by Friday")
        let changed = typed.proposedDeadline(now: wednesdayMorningInBogota, timeZone: bogota).addingTime(hour: 9, minute: 0)

        typed.confirmPicker(changed)
        typed.setText("Read paper", now: wednesdayMorningInBogota, timeZone: bogota, isKnownWord: englishOnly.contains)

        #expect(typed.deadline?.due == .timed(instant("2026-10-16T09:00:00-05:00")))
        #expect(typed.deadline?.isChosenByHand == true)
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
