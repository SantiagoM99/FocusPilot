import Foundation
import Testing
@testable import FocusPilotCore

@Suite("Weekly schedules")
struct WeeklyScheduleTests {
    private let workdays = WeeklySchedule(days: [.mon, .tue, .wed, .thu, .fri], from: ClockTime(8, 0), to: ClockTime(18, 0), timeZone: bogota)
    private let lateNights = WeeklySchedule(days: [.fri, .sat], from: ClockTime(22, 0), to: ClockTime(2, 0), timeZone: bogota)

    @Test(arguments: [
        ("2026-10-14T10:00:00-05:00", true),   // Wednesday morning
        ("2026-10-14T08:00:00-05:00", true),   // starts inclusive
        ("2026-10-14T18:00:00-05:00", false),  // ends exclusive
        ("2026-10-14T07:59:00-05:00", false),
        ("2026-10-17T10:00:00-05:00", false),  // Saturday
    ])
    func daytimeWindows(at iso: String, active: Bool) {
        #expect(workdays.contains(instant(iso)) == active)
    }

    @Test(arguments: [
        ("2026-10-16T23:00:00-05:00", true),   // Friday night
        ("2026-10-17T01:30:00-05:00", true),   // after midnight, still Friday's window
        ("2026-10-18T01:30:00-05:00", true),   // Saturday's window into Sunday
        ("2026-10-19T01:30:00-05:00", false),  // Sunday has no window
        ("2026-10-16T21:59:00-05:00", false),
    ])
    func overnightWindowsBelongToTheDayTheyStart(at iso: String, active: Bool) {
        #expect(lateNights.contains(instant(iso)) == active)
    }

    @Test func windowsFollowTheScheduleTimeZoneNotTheInstant() {
        // 08:30 in New York is 07:30 in Bogotá in October: before the window.
        #expect(!workdays.contains(instant("2026-10-14T08:30:00-04:00")))
    }

    @Test func nextChangeIsTheEndWhileActiveAndTheStartOtherwise() {
        #expect(workdays.nextChange(after: instant("2026-10-14T10:00:00-05:00")) == instant("2026-10-14T18:00:00-05:00"))
        #expect(workdays.nextChange(after: instant("2026-10-16T19:00:00-05:00")) == instant("2026-10-19T08:00:00-05:00"))
        #expect(lateNights.nextChange(after: instant("2026-10-16T23:00:00-05:00")) == instant("2026-10-17T02:00:00-05:00"))
    }

    @Test func aScheduleNeedsADayAndDifferentTimes() {
        #expect(workdays.isValid)
        #expect(!WeeklySchedule(days: [], from: ClockTime(8, 0), to: ClockTime(9, 0), timeZone: bogota).isValid)
        #expect(!WeeklySchedule(days: [.mon], from: ClockTime(8, 0), to: ClockTime(8, 0), timeZone: bogota).isValid)
    }

    @Test(arguments: [
        ([Weekday.mon, .tue, .wed, .thu, .fri], "Mon–Fri 08:00–18:00"),
        ([.sat, .sun], "Sat, Sun 08:00–18:00"),
        (Weekday.allCases, "Every day 08:00–18:00"),
        ([.mon, .wed, .thu, .fri, .sun], "Mon, Wed–Fri, Sun 08:00–18:00"),
    ])
    func summaries(days: [Weekday], text: String) {
        let schedule = WeeklySchedule(days: Set(days), from: ClockTime(8, 0), to: ClockTime(18, 0), timeZone: bogota)
        #expect(RuleText.summary(schedule) == text)
    }
}
