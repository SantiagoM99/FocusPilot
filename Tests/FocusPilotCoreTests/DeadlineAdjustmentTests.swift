import Foundation
import Testing
@testable import FocusPilotCore

@Suite("Deadline adjustments")
struct DeadlineAdjustmentTests {
    private let oct20 = Deadline(due: .dateOnly(LocalDate(year: 2026, month: 10, day: 20)), timeZone: bogota, originalText: "Oct 20")

    @Test func addingATimeMakesItTimedOnTheSameDay() {
        let timed = oct20.addingTime(hour: 23, minute: 59)

        #expect(timed.due == .timed(instant("2026-10-20T23:59:00-05:00")))
        #expect(timed.originalText == "Oct 20")
    }

    @Test func removingTheTimeKeepsTheLocalDay() {
        let lateNight = Deadline(due: .timed(instant("2026-10-20T23:30:00-05:00")), timeZone: bogota, originalText: "Oct 20 23:30")

        #expect(lateNight.removingTime().due == .dateOnly(LocalDate(year: 2026, month: 10, day: 20)))
    }

    @Test func changingTimeZoneKeepsTheWallClockTime() {
        let inBogota = Deadline(due: .timed(instant("2026-11-02T23:59:00-05:00")), timeZone: bogota, originalText: "Nov 2 23:59")

        let inNewYork = inBogota.changingTimeZone(to: newYork)

        #expect(inNewYork.due == .timed(instant("2026-11-02T23:59:00-05:00")))
        #expect(inBogota.changingTimeZone(to: TimeZone(identifier: "Europe/Madrid")!).due
            == .timed(instant("2026-11-02T23:59:00+01:00")))
    }

    @Test func changingTimeZoneOfADateOnlyDeadlineKeepsTheDay() {
        #expect(oct20.changingTimeZone(to: newYork).due == oct20.due)
        #expect(oct20.changingTimeZone(to: newYork).timeZone == newYork)
    }

    @Test func movingToAnotherDayKeepsTheTime() {
        let timed = oct20.addingTime(hour: 18, minute: 0)

        #expect(timed.moving(to: LocalDate(year: 2026, month: 11, day: 3)).due == .timed(instant("2026-11-03T18:00:00-05:00")))
        #expect(oct20.moving(to: LocalDate(year: 2026, month: 11, day: 3)).due == .dateOnly(LocalDate(year: 2026, month: 11, day: 3)))
    }
}

@Suite("LocalDate")
struct LocalDateTests {
    @Test(arguments: ["2026-10-x-20", "2026-10", "2026--10-20", "2026-1o-20", "2026-02-30", ""])
    func isoStringNeedsExactlyThreeNumericParts(_ text: String) {
        #expect(LocalDate(isoString: text) == nil)
    }

    @Test func isoStringRoundTrips() {
        #expect(LocalDate(isoString: "2026-10-20") == LocalDate(year: 2026, month: 10, day: 20))
        #expect(LocalDate(year: 2026, month: 1, day: 5).isoString == "2026-01-05")
    }
}
