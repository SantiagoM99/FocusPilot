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
        #expect(parse("Oct 20 12am")?.due == .timed(instant("2026-10-20T00:00:00-05:00")))
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

    @Test func missingYearPicksTheNearestOccurrence() {
        #expect(parse("Jan 5")?.due == .dateOnly(LocalDate(year: 2027, month: 1, day: 5)))
        #expect(parse("Oct 13")?.due == .dateOnly(LocalDate(year: 2026, month: 10, day: 13)))
        #expect(parse("Dec 30", now: instant("2027-01-02T09:00:00-05:00"))?.due
            == .dateOnly(LocalDate(year: 2026, month: 12, day: 30)))
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

    @Test func dateOnlyDeadlineOnTheDSTDayHasNoTime() {
        let now = instant("2026-10-14T10:00:00-04:00")

        #expect(parse("Nov 1", now: now, in: newYork)?.due == .dateOnly(LocalDate(year: 2026, month: 11, day: 1)))
    }

    // MARK: Rejected input

    @Test(arguments: ["", "   ", "soon", "next fri", "Feb 30", "fri 25:00", "13pm", "Oct", "fri banana"])
    func textThatIsNotFullyUnderstoodIsRejected(_ text: String) {
        #expect(parse(text) == nil)
    }
}
