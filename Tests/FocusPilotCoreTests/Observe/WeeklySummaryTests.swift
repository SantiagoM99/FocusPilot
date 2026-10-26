import Foundation
import Testing
@testable import FocusPilotCore

private let now = wednesdayMorningInBogota
private func ago(days: Double = 0, minutes: Double = 0) -> Date {
    now.addingTimeInterval(-(days * 86400 + minutes * 60))
}

@Suite("Weekly pilot summary")
struct WeeklySummaryTests {
    private let session = UUID()

    private var events: [PilotEvent] {
        [
            PilotEvent(kind: .sessionStarted, at: ago(days: 1), sessionID: session),
            PilotEvent(kind: .resume, at: ago(days: 1), duration: 8, sessionID: session),
            PilotEvent(kind: .distractionVisit, at: ago(days: 1, minutes: -5), duration: 120, target: "youtube.com", sessionID: session),
            PilotEvent(kind: .resume, at: ago(days: 1, minutes: -10), duration: 30, sessionID: session),
            PilotEvent(kind: .sessionEnded, at: ago(days: 1, minutes: -25), duration: 1500, sessionID: session),
            PilotEvent(kind: .sessionStarted, at: ago(days: 2)),
            PilotEvent(kind: .resume, at: ago(days: 2), duration: 12),
            PilotEvent(kind: .distractionVisit, at: ago(days: 3), duration: 600, target: "com.burbn.instagram"),
            PilotEvent(kind: .exceptionGranted, at: ago(days: 3), duration: 300),
            PilotEvent(kind: .blockedVisit, at: ago(days: 1, minutes: -7), target: "com.burbn.instagram", sessionID: session),
            PilotEvent(kind: .blockedVisit, at: ago(days: 4), target: "com.burbn.instagram"),
            // Older than a week: left out.
            PilotEvent(kind: .sessionStarted, at: ago(days: 8)),
            PilotEvent(kind: .distractionVisit, at: ago(days: 8), duration: 60, target: "youtube.com"),
        ]
    }

    @Test func itCountsTheLastSevenDays() {
        let summary = WeeklySummary(events: events, now: now)

        #expect(summary.sessionsStarted == 2)
        #expect(summary.sessionsEnded == 1)
        #expect(summary.resumes == 3)
        #expect(summary.medianResume == 12)
        #expect(summary.distractionVisits == 2)
        #expect(summary.distractionVisitsInSessions == 1)
        #expect(summary.distractionTime == 720)
        #expect(summary.exceptionsGranted == 1)
        #expect(summary.blockedVisits == 2)
        #expect(summary.blockedVisitsInSessions == 1)
    }

    @Test func itReadsAsPlainLines() {
        let summary = WeeklySummary(events: events, now: now)

        #expect(summary.lines == [
            WeeklySummary.Line(label: "Focus sessions", value: "2 started · 1 ended"),
            WeeklySummary.Line(label: "Resume time", value: "median 12 s · 3 resumes"),
            WeeklySummary.Line(label: "Distraction visits", value: "2 · 12 min · 1 during sessions"),
            WeeklySummary.Line(label: "Blocked visits", value: "2 · 1 during sessions"),
            WeeklySummary.Line(label: "Exceptions", value: "1 granted"),
        ])
    }

    @Test func anEmptyWeekSaysSo() {
        let lines = WeeklySummary(events: [], now: now).lines

        #expect(lines[0].value == "None yet")
        #expect(lines[1].value == "No resumes yet")
        #expect(lines[2].value == "None")
        #expect(lines[3].value == "None")
    }

    @Test func anEvenCountTakesTheMiddleTwo() {
        let resumes = [4.0, 10, 20, 90].map { PilotEvent(kind: .resume, at: ago(minutes: 1), duration: $0) }

        #expect(WeeklySummary(events: resumes, now: now).medianResume == 15)
        #expect(WeeklySummary(events: resumes, now: now).lines[1].value == "median 15 s · 4 resumes")
    }

    @Test func longResumesReadInMinutes() {
        let resumes = [PilotEvent(kind: .resume, at: ago(minutes: 1), duration: 150)]

        #expect(WeeklySummary(events: resumes, now: now).lines[1].value == "median 2 min 30 s · 1 resume")
    }
}

@Suite("Baseline week text")
struct BaselineWeekTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = bogota
        return calendar
    }

    @Test func theFirstDayIsDayOne() {
        let week = BaselineWeek(since: ago(minutes: 30), now: now, calendar: calendar)

        #expect(week.day == 1)
        #expect(week.menuLine == "Baseline week · day 1 of 7")
    }

    // Design 12: "4 of 7 days · since Fri 10 Oct".
    @Test func itCountsCalendarDaysSinceItStarted() {
        let week = BaselineWeek(since: ago(days: 3, minutes: 60), now: now, calendar: calendar)

        #expect(week.day == 4)
        #expect(week.menuLine == "Baseline week · day 4 of 7")
        #expect(week.observedLine == "4 of 7 days · since Sun 11 Oct")
    }

    @Test func pastAWeekItKeepsCounting() {
        let week = BaselineWeek(since: ago(days: 9), now: now, calendar: calendar)

        #expect(week.menuLine == "Observing · day 10")
        #expect(week.observedLine == "10 days · since Mon 5 Oct · the baseline week is done")
    }
}
