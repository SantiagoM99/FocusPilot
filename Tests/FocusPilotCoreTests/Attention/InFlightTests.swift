import Foundation
import Testing
@testable import FocusPilotCore

/// The redesign (#72): In flight is three flat sections, each row one thing
/// that moves without the owner.
@Suite("In flight")
struct InFlightTests {
    private typealias A = Attention

    private func board(tasks: [TodayItem], links: [TaskAgentLink] = [], reviews: [ReviewItem] = [],
                       waiting: [TaskWaiting] = []) -> InFlightBoard {
        InFlight.board(tasks: tasks, links: links, reviews: reviews, waiting: waiting, now: A.now, timeZone: bogota)
    }

    @Test func eachRowLandsInTheSectionItsAgentOrWaitPutsItIn() {
        let tasks = [A.task(10, "Approve"), A.task(11, "Result"), A.task(12, "Run"), A.task(13, "Hold"), A.task(14, "Due")]
        let links = [A.link(2, task: 10, "a", .blocked), A.link(3, task: 11, "b", .done), A.link(1, task: 12, "c", .working)]
        let reviews = [A.review(8, link: 2, task: 10, .approval, at: A.minutes(-2)),
                       A.review(7, link: 3, task: 11, .finished, at: A.minutes(-5))]
        let waiting = [TaskWaiting(taskID: 13, on: nil, since: A.minutes(-90), checkAt: A.minutes(30)),
                       TaskWaiting(taskID: 14, on: nil, since: A.minutes(-20), checkAt: A.minutes(-1))]

        let board = board(tasks: tasks, links: links, reviews: reviews, waiting: waiting)

        #expect(board.waitingOnYou.map(\.title) == ["Result", "Approve", "Due"], "Longest waited first among equal tasks")
        #expect(board.running.map(\.title) == ["Run"])
        #expect(board.waiting.map(\.title) == ["Hold"])
    }

    // An agent ready again after the owner saw its result is not moving.
    @Test func aReviewedIdleAgentIsNotInFlight() {
        #expect(board(tasks: [A.task(10, "Run ablation")], links: [A.link(1, task: 10, "a", .idle)]).rows.isEmpty)
    }

    // T20's order: the task's place, then its deadline, then the longest wait.
    @Test func runningRowsKeepTheOrderOfPriorityThenDeadlineThenLongestRunning() {
        let tasks = [A.task(1, "Later", status: .later), A.task(2, "Next late due", due: A.minutes(600)),
                     A.task(3, "Next soon due", due: A.minutes(60)), A.task(4, "Now", status: .now),
                     A.task(5, "Next no due, newer"), A.task(6, "Next no due, older")]
        let since = [1: -500.0, 2: -5, 3: -5, 4: -1, 5: -10, 6: -90]
        let links = tasks.map { A.link($0.id, task: $0.id, "a\($0.id)", .working, since: A.minutes(since[Int($0.id)]!)) }

        #expect(board(tasks: tasks, links: links).running.map(\.title)
            == ["Now", "Next soon due", "Next late due", "Next no due, older", "Next no due, newer", "Later"])
    }

    @Test func waitingRowsKeepTheSameOrder() {
        let tasks = [A.task(1, "Later", status: .later), A.task(2, "Next newer"), A.task(3, "Next older")]
        let waiting = [TaskWaiting(taskID: 1, on: nil, since: A.minutes(-500), checkAt: nil),
                       TaskWaiting(taskID: 2, on: nil, since: A.minutes(-5), checkAt: nil),
                       TaskWaiting(taskID: 3, on: nil, since: A.minutes(-50), checkAt: nil)]

        #expect(board(tasks: tasks, waiting: waiting).waiting.map(\.title) == ["Next older", "Next newer", "Later"])
    }

    // Decision 0004: no thread limit.
    @Test func thirtyFiveThreadsAreAllListed() {
        let tasks = (1...35).map { A.task(Int64(100 + $0), "Task \($0)") }
        let links = tasks.enumerated().map { index, task in
            A.link(Int64(index + 1), task: task.id, "agent \(index + 1)", index % 5 == 0 ? .blocked : .working)
        }
        let approvals = links.filter { $0.lastStatus == .blocked }.map { A.review($0.id, link: $0.id, task: $0.taskID, .approval, at: A.now) }

        let board = board(tasks: tasks, links: links, reviews: approvals)

        #expect(board.waitingOnYou.count == 7)
        #expect(board.running.count == 28)
    }

    @Test func onlyOpenTasksHaveRows() {
        let board = InFlight.board(tasks: [], links: [A.link(1, task: 10, "a", .working)], reviews: [],
                                   waiting: [TaskWaiting(taskID: 11, on: nil, since: A.now, checkAt: nil)], now: A.now, timeZone: bogota)

        #expect(board.rows.isEmpty)
    }

    // Review of #63: an approval cleared (its pane went away) leaves the link
    // blocked; In flight agrees with the queue and does not ask for the owner.
    @Test func aBlockedLinkWithNoApprovalWaitingIsNotInFlight() {
        #expect(board(tasks: [A.task(10, "Run ablation")], links: [A.link(1, task: 10, "plots", .blocked)]).rows.isEmpty)
    }

    @Test func reviewQueueListsResultsNotApprovals() {
        let tasks = [A.task(10, "Approve"), A.task(11, "Result")]
        let reviews = [A.review(8, link: 2, task: 10, .approval, at: A.minutes(-20)),
                       A.review(7, link: 3, task: 11, .finished, at: A.minutes(-5))]

        #expect(board(tasks: tasks, reviews: reviews).results.map(\.title) == ["Result"])
    }

    @Test func theSelectionFallsToTheFirstRowWhenItsRowIsGone() {
        let tasks = [A.task(10, "One"), A.task(11, "Two")]
        let links = [A.link(1, task: 10, "a", .working, since: A.minutes(-9)), A.link(2, task: 11, "b", .working, since: A.minutes(-1))]
        let board = board(tasks: tasks, links: links)

        #expect(InFlightRow.selected(.thread(.agent(2)), in: board.rows)?.title == "Two")
        #expect(InFlightRow.selected(.thread(.agent(99)), in: board.rows)?.title == "One")
        #expect(InFlightRow.selected(nil, in: []) == nil)
    }

    // The boards' copy, one row of each kind.
    @Test func aResultSaysWhereItCameFromAndHowLongItHasWaitedSinceTheAgentFinished() throws {
        let tasks = [A.task(10, "PhD shortlist", project: A.nlp)]
        let links = [A.link(3, task: 10, "drafts", .done, since: A.minutes(-300))]
        let reviews = [A.review(7, link: 3, task: 10, .finished, at: A.minutes(-12))]

        let row = try #require(board(tasks: tasks, links: links, reviews: reviews).waitingOnYou.first)

        #expect(row.detail == "NLP report · Herdr · Results ready · 12 min ago")
        #expect(row.statusLine == "Results ready · Herdr")
        #expect(row.action == .switchTo)
    }

    @Test func anApprovalIsAnsweredInTheAgent() throws {
        let links = [A.link(3, task: 10, "drafts", .blocked)]
        let reviews = [A.review(7, link: 3, task: 10, .approval, at: A.minutes(-3))]

        let row = try #require(board(tasks: [A.task(10, "Rebuttal")], links: links, reviews: reviews).waitingOnYou.first)

        #expect(row.detail == "Herdr · Approval requested · 3 min ago")
        #expect(row.statusLine == "Approval requested · Herdr")
        #expect(row.action == .openAgent)
    }

    @Test func aRunningRowHasItsTimeAndNoButton() throws {
        let links = [A.link(3, task: 10, "plots", .working, since: A.minutes(-41))]

        let row = try #require(board(tasks: [A.task(10, "Clean plots")], links: links).running.first)

        #expect(row.detail == "Herdr · Working · 41 min")
        #expect(row.statusLine == "Working · Herdr")
        #expect(row.action == nil)
    }

    @Test func twoAgentsOnOneTaskAreToldApartByName() {
        let links = [A.link(1, task: 10, "plots", .working, since: A.minutes(-9)), A.link(2, task: 10, "tables", .working, since: A.minutes(-5))]

        #expect(board(tasks: [A.task(10, "Run")], links: links).running.map(\.detail) == ["plots · Working · 9 min", "tables · Working · 5 min"])
    }

    @Test(arguments: [
        (TaskWaiting(taskID: 10, on: "advisor reply", since: A.minutes(-90), checkAt: instant("2026-10-15T09:00:00-05:00")), "Until Thu 09:00 · advisor reply"),
        (TaskWaiting(taskID: 10, on: nil, since: A.minutes(-90), checkAt: instant("2026-10-15T09:00:00-05:00")), "Until Thu 09:00"),
        (TaskWaiting(taskID: 10, on: "Ana", since: A.minutes(-90), checkAt: nil), "Waiting 1 h 30 min · Ana"),
        (TaskWaiting(taskID: 10, on: nil, since: A.minutes(-20), checkAt: nil), "Waiting 20 min"),
    ])
    func aWaitingRowSaysUntilWhenAndOnWhat(mark: TaskWaiting, expected: String) throws {
        let row = try #require(board(tasks: [A.task(10, "Proposal")], waiting: [mark]).waiting.first)

        #expect(row.detail == expected)
        #expect(row.statusLine == expected)
        #expect(row.action == .stopWaiting)
    }

    @Test func aDueCheckSaysSinceItWasDue() throws {
        let mark = TaskWaiting(taskID: 10, on: "Ana's review", since: A.minutes(-90), checkAt: A.minutes(-5))

        let row = try #require(board(tasks: [A.task(10, "Send")], waiting: [mark]).waitingOnYou.first)

        #expect(row.detail == "Check due · Ana's review · 5 min ago")
        #expect(row.action == .switchTo)
    }

    @Test(arguments: [(-0.5, "Just now"), (-1.0, "1 min ago"), (-125.0, "2 h 5 min ago"), (-120.0, "2 h ago")])
    func timesAreShortAndRounded(minutes: Double, expected: String) throws {
        let reviews = [A.review(7, link: 3, task: 10, .finished, at: A.minutes(minutes))]

        let row = try #require(board(tasks: [A.task(10, "Task")], reviews: reviews).waitingOnYou.first)

        #expect(row.detail == "Herdr · Results ready · \(expected)")
    }

    @Test func aReportHasNoTaskToSwitchTo() throws {
        let report = AgentReport(id: 1, clientID: UUID(), summary: "Done", projectID: 1, projectTitle: "NLP report",
                                 sourceLabel: "second", receivedAt: A.minutes(-4))

        let row = try #require(InFlight.board(tasks: [], links: [], reviews: [], waiting: [], reports: [report], now: A.now, timeZone: bogota).waitingOnYou.first)

        #expect(row.title == "second sent a report")
        #expect(row.detail == "NLP report · Report · 4 min ago")
        #expect(row.action == nil)
        #expect(row.switchRequest == nil)
    }

    // The sheet opens from any row that has a task, carrying what Switch clears.
    @Test func switchFromARowClearsTheResultItCameFrom() throws {
        let links = [A.link(3, task: 10, "drafts", .done)]
        let reviews = [A.review(7, link: 3, task: 10, .finished, at: A.minutes(-1), agent: "drafts")]

        let request = try #require(board(tasks: [A.task(10, "Task")], links: links, reviews: reviews).waitingOnYou.first?.switchRequest)

        #expect(request.taskID == 10 && request.linkID == 3 && request.item == .review(7))
    }
}
