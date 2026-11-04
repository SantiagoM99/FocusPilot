import Foundation
import Testing
@testable import FocusPilotCore

/// Reports join the attention queue (#67, decision 0004).
@Suite("Reports in the attention queue")
struct ReportAttentionTests {
    private typealias A = Attention

    private func stored(_ id: Int64, project: (Int64, String)?, at: Date, proposal: Bool = true) -> AgentReport {
        let target = ReportTarget(server: herdrServer, paneID: "w4:p2", name: "ablation", kind: "claude")
        return AgentReport(id: id, clientID: UUID(), summary: "The seed fix passes all 212 tests.", projectID: project?.0,
                           projectTitle: project?.1, sourceLabel: "second",
                           proposal: proposal ? ReportProposal(message: "Open the PR.", targetAsGiven: "ablation", target: target,
                                                               targetProblem: nil) : nil,
                           receivedAt: at)
    }

    @Test func aReportSaysWhoSentItAndWhatItProposes() {
        let items = AttentionQueue.items(tasks: [], reviews: [], waiting: [],
                                         reports: [stored(1, project: A.nlp, at: A.minutes(-5)),
                                                   stored(2, project: nil, at: A.minutes(-2), proposal: false)],
                                         now: A.now)

        #expect(items.map(\.id) == [.report(1), .report(2)])
        #expect(items.map(\.headline) == ["second proposes a message for ablation", "second sent a report"])
        #expect(items.map(\.place) == ["NLP report", "No project"])
        #expect(items[0].report?.summary == "The seed fix passes all 212 tests.")
        #expect(items[0].taskID == nil)
        #expect(items[0].waitingSince == A.minutes(-5))
    }

    @Test func aReportOnTheNowTasksProjectRanksWithNowOthersWithNext() {
        let tasks = [A.task(10, "Write §4", project: A.nlp, status: .now), A.task(11, "Fix the build", project: A.app),
                     A.task(12, "Tidy", status: .later)]
        let reviews = [A.review(1, link: 1, task: 11, .finished, at: A.minutes(-20)),
                       A.review(2, link: 2, task: 12, .finished, at: A.minutes(-90))]
        let reports = [stored(5, project: A.app, at: A.minutes(-30)), stored(6, project: A.nlp, at: A.minutes(-1))]

        let items = AttentionQueue.items(tasks: tasks, reviews: reviews, waiting: [], reports: reports, now: A.now)

        #expect(items.map(\.id) == [.report(6), .report(5), .review(1), .review(2)],
                "Now's project first; then Next, oldest wait first; then Later")
    }

    @Test func aReportIsNotSomethingToSwitchTo() {
        let item = AttentionQueue.items(tasks: [], reviews: [], waiting: [], reports: [stored(1, project: A.nlp, at: A.now)],
                                        now: A.now)[0]

        #expect(SwitchRequest(item) == nil)
    }
}
