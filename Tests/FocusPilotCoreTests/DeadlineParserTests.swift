import Foundation
import Testing
@testable import FocusPilotCore

@Suite("DeadlineParser")
struct DeadlineParserTests {
    private func parse(_ text: String, now: Date = wednesdayMorningInBogota, in timeZone: TimeZone = bogota) -> Deadline? {
        DeadlineParser(now: now, timeZone: timeZone).parse(text)
    }

    // MARK: Timed deadlines

    @Test func weekdayWithTimeIsTheComingWeekdayInBogota() {
        let deadline = parse("fri 23:59")

        #expect(deadline?.due == .timed(instant("2026-10-16T23:59:00-05:00")))
        #expect(deadline?.timeZone == bogota)
        #expect(deadline?.originalText == "fri 23:59")
    }

    @Test func fillerWordsAndTwelveHourTimesAreUnderstood() {
        #expect(parse("by Friday 11pm")?.due == .timed(instant("2026-10-16T23:00:00-05:00")))
        #expect(parse("due Oct 20 at 9:30 am")?.due == .timed(instant("2026-10-20T09:30:00-05:00")))
        #expect(parse("Oct 20 noon")?.due == .timed(instant("2026-10-20T12:00:00-05:00")))
        #expect(parse("Oct 20 12pm")?.due == .timed(instant("2026-10-20T12:00:00-05:00")))
        #expect(parse("Oct 20 00:00")?.due == .timed(instant("2026-10-20T00:00:00-05:00")))
    }

    // People usually mean the end of the day, which is the next day's 00:00.
    @Test(arguments: ["Oct 20 12am", "Oct 20 12:00am", "Oct 20 12 am", "Oct 20 midnight"])
    func midnightWordsAreRejectedWithAHint(_ text: String) {
        #expect(parse(text) == nil)
        #expect(DeadlineParser.hint(for: text).contains("23:59"))
    }

    @Test func otherUnreadableTextGetsTheGeneralHint() {
        #expect(DeadlineParser.hint(for: "soon") == "Could not read this deadline. Try “fri 23:59”, “Oct 20” or “2026-10-20”.")
    }

    @Test func timeAloneMeansToday() {
        #expect(parse("17:00")?.due == .timed(instant("2026-10-14T17:00:00-05:00")))
    }

    @Test func todayCountsAsTheComingWeekday() {
        #expect(parse("wed 18:00")?.due == .timed(instant("2026-10-14T18:00:00-05:00")))
    }

    // MARK: Date-only deadlines

    @Test func monthAndDayWithoutTimeStaysDateOnly() {
        let deadline = parse("Oct 16")

        #expect(deadline?.due == .dateOnly(LocalDate(year: 2026, month: 10, day: 16)))
        #expect(deadline?.timeZone == bogota)
    }

    @Test func dateOnlyFormsAreAccepted() {
        let oct20 = Deadline.Due.dateOnly(LocalDate(year: 2026, month: 10, day: 20))
        #expect(parse("by Oct 20")?.due == oct20)
        #expect(parse("20 October")?.due == oct20)
        #expect(parse("October 20th, 2026")?.due == oct20)
        #expect(parse("2026-10-20")?.due == oct20)
        #expect(parse("tomorrow")?.due == .dateOnly(LocalDate(year: 2026, month: 10, day: 15)))
        #expect(parse("today")?.due == .dateOnly(LocalDate(year: 2026, month: 10, day: 14)))
    }

    @Test(arguments: [
        ("May 1", LocalDate(year: 2027, month: 5, day: 1)),
        ("Jan 5", LocalDate(year: 2027, month: 1, day: 5)),
        ("Oct 13", LocalDate(year: 2026, month: 10, day: 13)),
        ("Oct 7", LocalDate(year: 2026, month: 10, day: 7)),
        ("Oct 6", LocalDate(year: 2027, month: 10, day: 6)),
    ])
    func missingYearPicksTheNextOccurrenceLookingBackAWeek(text: String, expected: LocalDate) {
        #expect(parse(text)?.due == .dateOnly(expected))
    }

    @Test func lookBackCrossesNewYear() {
        #expect(parse("Dec 30", now: instant("2027-01-02T09:00:00-05:00"))?.due
            == .dateOnly(LocalDate(year: 2026, month: 12, day: 30)))
    }

    @Test func spanishRelativeDaysAreUnderstood() {
        #expect(parse("hoy 17:00")?.due == .timed(instant("2026-10-14T17:00:00-05:00")))
        #expect(parse("mañana 10:00")?.due == .timed(instant("2026-10-15T10:00:00-05:00")))
        #expect(parse("Mañana")?.due == .dateOnly(LocalDate(year: 2026, month: 10, day: 15)))
        #expect(parse("para pasado mañana")?.due == .dateOnly(LocalDate(year: 2026, month: 10, day: 16)))
        #expect(parse("el 20 Oct")?.due == .dateOnly(LocalDate(year: 2026, month: 10, day: 20)))
    }

    @Test func spanishWeekdaysAndMonthsAreUnderstood() {
        #expect(parse("el viernes")?.due == .dateOnly(LocalDate(year: 2026, month: 10, day: 16)))
        #expect(parse("para el miércoles 9:00")?.due == .timed(instant("2026-10-14T09:00:00-05:00")))
        #expect(parse("el miercoles")?.due == .dateOnly(LocalDate(year: 2026, month: 10, day: 14)))
        #expect(parse("antes del sábado")?.due == .dateOnly(LocalDate(year: 2026, month: 10, day: 17)))
        #expect(parse("el sabado 18:00")?.due == .timed(instant("2026-10-17T18:00:00-05:00")))
        #expect(parse("para el 20 de octubre")?.due == .dateOnly(LocalDate(year: 2026, month: 10, day: 20)))
        #expect(parse("el 3 de enero de 2027")?.due == .dateOnly(LocalDate(year: 2027, month: 1, day: 3)))
        #expect(parse("el 15 de setiembre")?.due == .dateOnly(LocalDate(year: 2027, month: 9, day: 15)))
    }

    @Test func isoDatesMustBeStrictAndPlausible() {
        #expect(parse("2-3-4") == nil)
        #expect(parse("2026-1-5") == nil)
        #expect(parse("0002-03-04") == nil)
        #expect(parse("2040-03-04") == nil)
        #expect(parse("2027-03-04")?.due == .dateOnly(LocalDate(year: 2027, month: 3, day: 4)))
    }

    @Test func yearsAreAcceptedFromLastYearToTenYearsAhead() {
        #expect(parse("Oct 16 2025")?.due == .dateOnly(LocalDate(year: 2025, month: 10, day: 16)))
        #expect(parse("Oct 16 2036")?.due == .dateOnly(LocalDate(year: 2036, month: 10, day: 16)))
        #expect(parse("Oct 16 2024") == nil)
        #expect(parse("Oct 16 2037") == nil)
    }

    // MARK: next / this weekday

    @Test(arguments: [
        ("next fri", LocalDate(year: 2026, month: 10, day: 23)),
        ("next mon", LocalDate(year: 2026, month: 10, day: 19)),
        ("next wed", LocalDate(year: 2026, month: 10, day: 21)),
        ("next sun", LocalDate(year: 2026, month: 10, day: 25)),
        ("this fri", LocalDate(year: 2026, month: 10, day: 16)),
        ("this wed", LocalDate(year: 2026, month: 10, day: 14)),
    ])
    func nextMeansTheFollowingMondayStartedWeek(text: String, expected: LocalDate) {
        #expect(parse(text)?.due == .dateOnly(expected))
    }

    @Test func nextWeekdayTakesATime() {
        #expect(parse("by next fri 17:00")?.due == .timed(instant("2026-10-23T17:00:00-05:00")))
    }

    // MARK: Past deadlines

    @Test func pastDeadlinesAreKeptAsEntered() {
        #expect(parse("2026-10-01")?.due == .dateOnly(LocalDate(year: 2026, month: 10, day: 1)))
        #expect(parse("Oct 13 18:00")?.due == .timed(instant("2026-10-13T18:00:00-05:00")))
        #expect(parse("8:00")?.due == .timed(instant("2026-10-14T08:00:00-05:00")))
    }

    // MARK: Daylight saving time (New York; Bogotá has none)

    @Test func timedDeadlineAfterDSTEndsKeepsItsWallClockTime() {
        let now = instant("2026-10-14T10:00:00-04:00")

        let deadline = parse("Nov 2 23:59", now: now, in: newYork)

        #expect(deadline?.due == .timed(instant("2026-11-02T23:59:00-05:00")))
    }

    @Test func timeInsideTheSpringForwardGapMovesToTheFirstValidInstant() {
        let now = instant("2026-03-01T10:00:00-05:00")

        let deadline = parse("Mar 8 2:30", now: now, in: newYork)

        #expect(deadline?.due == .timed(instant("2026-03-08T03:30:00-04:00")))
    }

    @Test func timeRepeatedWhenDSTEndsTakesTheFirstOccurrence() {
        let now = instant("2026-10-14T10:00:00-04:00")

        let deadline = parse("Nov 1 1:30am", now: now, in: newYork)

        #expect(deadline?.due == .timed(instant("2026-11-01T01:30:00-04:00")))
        #expect(deadline.map { DeadlineText($0).kind } == "Timed · America/New_York (GMT−4)")
    }

    @Test func dateOnlyDeadlineOnTheDSTDayHasNoTime() {
        let now = instant("2026-10-14T10:00:00-04:00")

        #expect(parse("Nov 1", now: now, in: newYork)?.due == .dateOnly(LocalDate(year: 2026, month: 11, day: 1)))
    }

    // MARK: Rejected input

    @Test(arguments: ["", "   ", "soon", "next", "next oct", "this", "Feb 30", "fri 25:00", "13pm", "Oct", "fri banana",
                      "Oct 16 2359", "Oct 16 1130"])
    func textThatIsNotFullyUnderstoodIsRejected(_ text: String) {
        #expect(parse(text) == nil)
    }
}
