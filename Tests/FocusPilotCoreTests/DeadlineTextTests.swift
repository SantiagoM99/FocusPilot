import Foundation
import Testing
@testable import FocusPilotCore

@Suite("DeadlineText")
struct DeadlineTextTests {
    private func text(_ typed: String, timeZone: TimeZone = bogota) -> DeadlineText {
        DeadlineText(DeadlineParser(now: wednesdayMorningInBogota, timeZone: timeZone).parse(typed)!)
    }

    // MARK: Preview before saving

    @Test func timedPreviewShowsExactTimeAndZone() {
        let preview = text("by Friday 11pm")

        #expect(preview.exact == "Fri 16 Oct 2026, 23:00")
        #expect(preview.kind == "Timed · America/Bogota (GMT−5)")
        #expect(preview.source == "from “by Friday 11pm”")
    }

    @Test func dateOnlyPreviewSaysNoTimeWasAssumed() {
        let preview = text("by Oct 20")

        #expect(preview.exact == "Tue 20 Oct 2026")
        #expect(preview.kind == "Date only · stays on the local date in America/Bogota")
        #expect(preview.source == "from “by Oct 20” · no time given, none assumed")
    }

    @Test func zoneOffsetIsTheOneInForceOnTheDeadline() {
        let afterDSTEnds = DeadlineText(Deadline(
            due: .timed(instant("2026-11-02T23:59:00-05:00")), timeZone: newYork, originalText: "Nov 2 23:59"))

        #expect(afterDSTEnds.exact == "Mon 2 Nov 2026, 23:59")
        #expect(afterDSTEnds.kind == "Timed · America/New_York (GMT−5)")
    }

    @Test func halfHourOffsetsKeepTheirMinutes() {
        let kolkata = TimeZone(identifier: "Asia/Kolkata")!

        #expect(text("Oct 20 9:00", timeZone: kolkata).kind == "Timed · Asia/Kolkata (GMT+5:30)")
    }

    // MARK: Relative label in Today

    @Test(arguments: [
        ("17:00", "Due today 17:00"),
        ("today", "Due today"),
        ("tomorrow", "Due tomorrow"),
        ("fri 23:59", "Due Fri 23:59"),
        ("Oct 20", "Due Tue"),
        ("Oct 21", "Due Wed 21 Oct"),
        ("Oct 31 18:00", "Due Sat 31 Oct, 18:00"),
        ("Jan 5", "Due Tue 5 Jan 2027"),
    ])
    func upcomingDeadlinesReadRelativeToNow(typed: String, label: String) {
        #expect(text(typed).relative(at: wednesdayMorningInBogota) == label)
    }

    @Test func pastDeadlinesReadAsOverdueWithTheirExactTime() {
        #expect(text("Oct 13 18:00").relative(at: wednesdayMorningInBogota) == "Overdue · Tue 13 Oct, 18:00")
        #expect(text("8:00").relative(at: wednesdayMorningInBogota) == "Overdue · today 08:00")
        #expect(text("2026-10-01").relative(at: wednesdayMorningInBogota) == "Overdue · Thu 1 Oct")
    }

    @Test func dateOnlyDeadlineIsNotOverdueUntilItsDayEnds() {
        let lateToday = instant("2026-10-14T23:59:00-05:00")

        #expect(text("today").relative(at: lateToday) == "Due today")
        #expect(text("today").relative(at: instant("2026-10-15T00:00:00-05:00")) == "Overdue · Wed 14 Oct")
    }

    @Test func inspectionShowsExactDateTimeAndZone() {
        #expect(text("fri 23:59").inspection == "Fri 16 Oct 2026, 23:59 · America/Bogota (GMT−5)")
        #expect(text("Oct 20").inspection == "Tue 20 Oct 2026 · date only · America/Bogota")
    }
}
