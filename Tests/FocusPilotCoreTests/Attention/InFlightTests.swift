import Foundation
import Testing
@testable import FocusPilotCore

/// Decision 0004: In flight lists threads that move without the owner,
/// grouped by project, each working, needing the owner, finished or waiting.
@Suite("In flight")
struct InFlightTests {
    private typealias A = Attention

    @Test func eachAgentThreadTakesItsStateFromWhatHerdrLastSaid() {
        let tasks = [A.task(10, "Run ablation", project: A.nlp)]
        let links = [A.link(1, task: 10, "ablation", .working), A.link(2, task: 10, "plots", .blocked),
                     A.link(3, task: 10, "tables", .done), A.link(4, task: 10, "idle", .idle)]
        let reviews = [A.review(7, link: 3, task: 10, .finished, at: A.minutes(-5))]

        let projects = InFlight.projects(tasks: tasks, links: links, reviews: reviews, waiting: [], now: A.now)

        let states = projects.first?.threads.map { ($0.label, $0.state) }
        #expect(states?.map(\.0) == ["plots", "tables", "ablation"], "Needs you, finished, then working")
        #expect(states?.map(\.1) == [.needsYou, .finished, .working])
        #expect(projects.first?.threads.first { $0.label == "tables" }?.since == A.minutes(-5))
    }

    // An agent ready again after the owner saw its result is not moving.
    @Test func aReviewedIdleAgentIsNotInFlight() {
        let projects = InFlight.projects(tasks: [A.task(10, "Run ablation")], links: [A.link(1, task: 10, "a", .idle)],
                                         reviews: [], waiting: [], now: A.now)

        #expect(projects.isEmpty)
    }

    @Test func aTaskMarkedWaitingIsAThreadUntilItsCheckIsDue() {
        let tasks = [A.task(10, "Send the draft", project: A.app), A.task(11, "Book the room", project: A.app)]
        let waiting = [TaskWaiting(taskID: 10, on: "Ana's review", since: A.minutes(-90), checkAt: A.minutes(30)),
                       TaskWaiting(taskID: 11, on: nil, since: A.minutes(-20), checkAt: A.minutes(-1))]

        let threads = InFlight.projects(tasks: tasks, links: [], reviews: [], waiting: waiting, now: A.now)[0].threads

        #expect(threads.map(\.label) == ["Waiting", "Waiting on Ana's review"])
        #expect(threads.map(\.state) == [.needsYou, .waiting])
    }

    @Test func projectsAreSummarizedAndOrderedLikeTheProjectsList() {
        let tasks = [A.task(10, "Run ablation", project: A.nlp), A.task(11, "Fix parser", project: A.app),
                     A.task(12, "Call the bank")]
        let links = [A.link(1, task: 10, "a", .working), A.link(2, task: 10, "b", .blocked), A.link(3, task: 10, "c", .blocked),
                     A.link(4, task: 11, "d", .working), A.link(5, task: 12, "e", .working)]

        let projects = InFlight.projects(tasks: tasks, links: links, reviews: [], waiting: [], now: A.now)

        #expect(projects.map(\.title) == ["FocusPilot", "NLP report", "No project"])
        #expect(projects.map(\.summary) == ["FocusPilot · 1 thread", "NLP report · 3 threads · 2 need you",
                                            "No project · 1 thread"])
    }

    // Decision 0004: no thread limit.
    @Test func thirtyFiveThreadsAcrossSixProjectsAreAllListed() {
        let projects = (1...6).map { (Int64($0), "Project \($0)") }
        let tasks = (1...35).map { A.task(Int64(100 + $0), "Task \($0)", project: projects[$0 % 6]) }
        let links = tasks.enumerated().map { index, task in
            A.link(Int64(index + 1), task: task.id, "agent \(index + 1)", index % 5 == 0 ? .blocked : .working)
        }

        let grouped = InFlight.projects(tasks: tasks, links: links, reviews: [], waiting: [], now: A.now)

        #expect(grouped.count == 6)
        #expect(grouped.map(\.threads.count).reduce(0, +) == 35)
        #expect(grouped.map(\.needsYou).reduce(0, +) == 7)
    }

    @Test func onlyOpenTasksHaveThreads() {
        let projects = InFlight.projects(tasks: [], links: [A.link(1, task: 10, "a", .working)], reviews: [],
                                         waiting: [TaskWaiting(taskID: 11, on: nil, since: A.now, checkAt: nil)], now: A.now)

        #expect(projects.isEmpty)
    }
}
