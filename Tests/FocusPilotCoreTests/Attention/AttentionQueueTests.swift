import Foundation
import Testing
@testable import FocusPilotCore

/// Decision 0004: the attention queue holds only what needs the owner now,
/// ordered by priority, then deadline, then how long it has waited.
@Suite("Attention queue")
struct AttentionQueueTests {
    private typealias A = Attention

    @Test func itHoldsApprovalsResultsAndDueChecksOnly() {
        let tasks = [A.task(10, "Run ablation", project: A.nlp), A.task(11, "Send the draft")]
        let reviews = [A.review(1, link: 1, task: 10, .approval, at: A.minutes(-3), title: "Run ablation", agent: "plots"),
                       A.review(2, link: 2, task: 10, .finished, at: A.minutes(-8), title: "Run ablation", agent: "ablation")]
        let waiting = [TaskWaiting(taskID: 11, on: "Ana's review", since: A.minutes(-120), checkAt: A.minutes(-10)),
                       TaskWaiting(taskID: 10, on: nil, since: A.minutes(-5), checkAt: A.minutes(20))]

        let items = AttentionQueue.items(tasks: tasks, reviews: reviews, waiting: waiting, now: A.now)

        #expect(items.map(\.id) == [.check(11), .review(2), .review(1)], "Oldest wait first when nothing else differs")
        #expect(items.map(\.headline) == ["Time to check on Ana's review", "ablation finished", "plots needs your approval"])
        #expect(items[1].place == "Run ablation · NLP report")
    }

    @Test func priorityComesFirstThenDeadlineThenWaitingTime() {
        let tasks = [A.task(10, "Later, long wait", status: .later),
                     A.task(11, "Next, no deadline"),
                     A.task(12, "Next, due tomorrow", due: A.minutes(24 * 60)),
                     A.task(13, "Next, due tonight", due: A.minutes(8 * 60)),
                     A.task(14, "Now, no deadline", status: .now)]
        let reviews = tasks.enumerated().map { index, task in
            A.review(Int64(index + 1), link: Int64(index + 1), task: task.id, .finished, at: A.minutes(Double(-100 + index)))
        }

        let items = AttentionQueue.items(tasks: tasks, reviews: reviews, waiting: [], now: A.now)

        #expect(items.map(\.taskID) == [14, 13, 12, 11, 10], "Now, then Next by deadline, then Later")
    }

    // Waiting time runs from the moment the agent needed the owner.
    @Test func afterThirtyMinutesAnItemGetsAQuietAlert() {
        let item = AttentionQueue.items(tasks: [A.task(10, "Run ablation")],
                                        reviews: [A.review(1, link: 1, task: 10, .approval, at: A.minutes(-34))],
                                        waiting: [], now: A.now)[0]

        #expect(item.waitingSince == A.minutes(-34))
        #expect(item.needsAlert(at: A.now))
        #expect(!item.needsAlert(at: A.minutes(-5)))
        #expect(AttentionText.waited(item, at: A.now) == "Waiting 34 min")
        #expect(AttentionText.waited(item, at: A.minutes(-34 + 0.5)) == "Just now")
        #expect(AttentionText.waited(item, at: A.minutes(-34 + 65)) == "Waiting 1 h 5 min")
    }

    @Test func itemsForTasksNoLongerOpenAreLeftOut() {
        let items = AttentionQueue.items(tasks: [], reviews: [A.review(1, link: 1, task: 10, .finished, at: A.now)],
                                         waiting: [], now: A.now)

        #expect(items.isEmpty)
    }

    @Test func thirtyFiveItemsAreAllQueued() {
        let tasks = (1...35).map { A.task(Int64($0), "Task \($0)") }
        let reviews = tasks.map { A.review($0.id, link: $0.id, task: $0.id, .finished, at: A.minutes(Double(-$0.id))) }

        #expect(AttentionQueue.items(tasks: tasks, reviews: reviews, waiting: [], now: A.now).count == 35)
    }
}

@Suite("Check again choices")
struct WaitingCheckTests {
    @Test func eachChoiceIsATimeFromNow() {
        let now = wednesdayMorningInBogota
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = bogota

        #expect(WaitingCheck.none.date(after: now, calendar: calendar) == nil)
        #expect(WaitingCheck.inThirtyMinutes.date(after: now, calendar: calendar) == now.addingTimeInterval(30 * 60))
        #expect(WaitingCheck.inThreeHours.date(after: now, calendar: calendar) == now.addingTimeInterval(3 * 3600))
        let tomorrow = WaitingCheck.tomorrowMorning.date(after: now, calendar: calendar)
        #expect(tomorrow.map { calendar.dateComponents([.day, .hour, .minute], from: $0) }
            == calendar.dateComponents([.day, .hour, .minute], from: calendar.date(bySettingHour: 9, minute: 0, second: 0,
                                                                                      of: now.addingTimeInterval(86_400))!))
        #expect(WaitingCheck.allCases.map(\.title) == ["No time set", "In 30 minutes", "In 1 hour", "In 3 hours",
                                                      "Tomorrow at 9:00"])
    }
}

// Review of #63: waiting times change by the minute, so the app recomputes
// them once a minute; only a countdown on screen ticks every second.
@Suite("Attention clock")
struct AttentionClockTests {
    private let start = wednesdayMorningInBogota

    @Test func waitingTimesAdvanceOnceAMinute() {
        #expect(!AttentionClock.isDue(at: start.addingTimeInterval(30), last: start, somethingWaits: true))
        #expect(AttentionClock.isDue(at: start.addingTimeInterval(60), last: start, somethingWaits: true))
        #expect(!AttentionClock.isDue(at: start.addingTimeInterval(600), last: start, somethingWaits: false),
                "Nothing waiting, nothing to redraw")
    }
}
