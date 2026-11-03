import Foundation
import Testing
@testable import FocusPilotCore

/// What VoiceOver hears and what Reduce Motion shows (#23).
@Suite("Accessibility text")
struct AccessibilityTextTests {
    private let now = wednesdayMorningInBogota

    private func timed(_ iso: String) -> Deadline {
        Deadline(due: .timed(instant(iso)), timeZone: bogota, originalText: iso)
    }

    private func dateOnly(_ year: Int, _ month: Int, _ day: Int) -> Deadline {
        Deadline(due: .dateOnly(LocalDate(year: year, month: month, day: day)), timeZone: bogota, originalText: "")
    }

    // MARK: Spoken deadlines, without the middle dots of the visible text

    @Test func aDeadlineIsSpokenWithFullDayAndMonthNames() {
        #expect(DeadlineText(dateOnly(2026, 10, 20)).spoken(at: now) == "due Tuesday 20 October")
        #expect(DeadlineText(timed("2026-10-16T23:59:00-05:00")).spoken(at: now) == "due Friday 16 October at 23:59, Bogotá time")
    }

    @Test func todayAndTomorrowAreSpokenAsSuch() {
        #expect(DeadlineText(timed("2026-10-14T17:00:00-05:00")).spoken(at: now) == "due today at 17:00, Bogotá time")
        #expect(DeadlineText(dateOnly(2026, 10, 15)).spoken(at: now) == "due tomorrow")
    }

    @Test func anOverdueDeadlineSaysSince() {
        #expect(DeadlineText(timed("2026-10-13T18:00:00-05:00")).spoken(at: now) == "overdue since Tuesday 13 October at 18:00, Bogotá time")
        #expect(DeadlineText(dateOnly(2026, 10, 12)).spoken(at: now) == "overdue since Monday 12 October")
    }

    @Test func anotherYearIsSpoken() {
        #expect(DeadlineText(dateOnly(2027, 1, 4)).spoken(at: now) == "due Monday 4 January 2027")
    }

    // MARK: Task rows read as one item

    @Test func aTaskRowIsOneSentence() {
        let item = TodayItem(id: 1, title: "PhD shortlist", projectTitle: "Applications", deadline: dateOnly(2026, 10, 20))
        #expect(item.spokenLabel(showsProject: true, at: now) == "PhD shortlist, Applications, due Tuesday 20 October")
        #expect(item.spokenLabel(showsProject: false, at: now) == "PhD shortlist, due Tuesday 20 October")
    }

    @Test func aTaskWithoutDeadlineOrProjectSaysSo() {
        let item = TodayItem(id: 1, title: "Reply to co-advisor")
        #expect(item.spokenLabel(showsProject: true, at: now) == "Reply to co-advisor, no deadline")
    }

    @Test func aTaskFromHerdrSaysWhereItCameFrom() {
        let item = TodayItem(id: 1, title: "Fix flaky test", projectTitle: "NLP report", isFromHerdr: true)
        #expect(item.spokenLabel(showsProject: true, at: now) == "Fix flaky test, NLP report, no deadline, added from Herdr")
    }

    // MARK: Reduce Motion: whole minutes, rounded up

    @Test func theMenuBarTimeReadsInMinutesWithReduceMotion() {
        var session = FocusSession.sample(phase: .running)
        session.plannedEnd = now.addingTimeInterval(24 * 60 + 8)
        let snapshot = FocusSnapshot(session: session)

        let reduced = MenuBarStatus(snapshot: snapshot, now: now, showsTime: true, reducesMotion: true)
        #expect(reduced.timeText == "25 min")
        #expect(reduced.accessibilityLabel.hasSuffix(", 25 min left"))
        #expect(MenuBarStatus(snapshot: snapshot, now: now, showsTime: true).timeText == "24:08")
    }

    @Test func theHiddenAppPanelReadsInMinutesWithReduceMotion() {
        var session = FocusSession.sample(phase: .running)
        session.plannedEnd = now.addingTimeInterval(24 * 60 + 8)
        let text = BlockedAppText(appName: "Instagram", reason: .always, session: session, at: now, reducesMotion: true)
        #expect(text.headline == "Focus session · 25 min left")
    }

    // MARK: Attention items read as one sentence, with units spelled out

    @Test func anAttentionItemIsOneSentence() {
        let item = AttentionQueue.items(tasks: [Attention.task(10, "Run ablation", project: Attention.nlp)],
                                        reviews: [Attention.review(1, link: 1, task: 10, .approval, at: Attention.minutes(-34), agent: "plots")],
                                        waiting: [], now: Attention.now)[0]
        #expect(AttentionText.spoken(item, at: Attention.now) == "plots needs your approval, Run ablation, NLP report, waiting 34 minutes")
        #expect(AttentionText.spoken(item, at: Attention.minutes(-34 + 65)).hasSuffix(", waiting 1 hour 5 minutes"))
        #expect(AttentionText.spoken(item, at: Attention.minutes(-34 + 1)).hasSuffix(", waiting 1 minute"))
        #expect(AttentionText.spoken(item, at: Attention.minutes(-34 + 120)).hasSuffix(", waiting 2 hours"))
        #expect(AttentionText.spoken(item, at: Attention.minutes(-34 + 0.5)).hasSuffix(", just now"))
    }

    @Test func anAttentionItemWithoutProjectLeavesItOut() {
        let item = AttentionQueue.items(tasks: [Attention.task(10, "Run ablation")],
                                        reviews: [Attention.review(1, link: 1, task: 10, .finished, at: Attention.minutes(-5), agent: "ablation")],
                                        waiting: [], now: Attention.now)[0]
        #expect(AttentionText.spoken(item, at: Attention.now) == "ablation finished, Run ablation, waiting 5 minutes")
    }
}
