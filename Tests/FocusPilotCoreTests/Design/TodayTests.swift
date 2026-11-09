import Foundation
import Testing
@testable import FocusPilotCore

/// #71: the words and choices behind Today, the inspector and the sheets
/// (docs/design/redesign-2026-11, Main and Sheets).
@Suite("Today redesign")
struct TodayTests {
    private func text(_ typed: String) -> DeadlineText {
        DeadlineText(DeadlineParser(now: wednesdayMorningInBogota, timeZone: bogota).parse(typed)!)
    }

    private func deadline(_ typed: String) -> Deadline {
        DeadlineParser(now: wednesdayMorningInBogota, timeZone: bogota).parse(typed)!
    }

    // MARK: Row deadlines

    @Test(arguments: [
        ("17:00", "Today"),
        ("tomorrow", "Tomorrow"),
        ("fri 23:59", "Fri"),
        ("Oct 20", "Tue"),
        ("Oct 21", "21 Oct"),
        ("Jan 5", "5 Jan 2027"),
        ("Oct 13 18:00", "Overdue"),
    ])
    func rowsShowAShortDeadline(typed: String, label: String) {
        #expect(text(typed).short(at: wednesdayMorningInBogota) == label)
    }

    // MARK: Inspector and capture deadlines

    @Test(arguments: [
        ("fri 17:00", "Fri 16 Oct, 17:00"),
        ("Oct 20", "Tue 20 Oct"),
        ("Jan 5 9:00", "Tue 5 Jan 2027, 09:00"),
    ])
    func theInspectorShowsDayAndTimeWithoutTheCurrentYear(typed: String, label: String) {
        #expect(text(typed).dayAndTime(at: wednesdayMorningInBogota) == label)
    }

    // MARK: Now card line

    @Test func theNowLineJoinsProjectAndNextAction() {
        let item = TodayItem(id: 1, title: "Explain", projectTitle: "NLP report", nextAction: "write the table")

        #expect(item.nowLine(showsProject: true) == "NLP report · Next: write the table")
    }

    @Test func theNowLineLeavesOutWhatIsMissing() {
        #expect(TodayItem(id: 1, title: "A", nextAction: "write").nowLine(showsProject: true) == "Next: write")
        #expect(TodayItem(id: 1, title: "A", projectTitle: "NLP").nowLine(showsProject: true) == "NLP")
        #expect(TodayItem(id: 1, title: "A").nowLine(showsProject: true) == nil)
    }

    @Test func insideAProjectTheNowLineHasNoProject() {
        let item = TodayItem(id: 1, title: "A", projectTitle: "NLP", nextAction: "write")

        #expect(item.nowLine(showsProject: false) == "Next: write")
    }

    // MARK: Start focus summary

    @Test func theStartFocusSummaryJoinsProjectAndDeadline() {
        let item = TodayItem(id: 1, title: "A", projectTitle: "NLP report", deadline: deadline("fri 23:59"))

        #expect(item.focusSummary(at: wednesdayMorningInBogota) == "NLP report · Due Fri 23:59")
    }

    @Test func theStartFocusSummaryLeavesOutWhatIsMissing() {
        #expect(TodayItem(id: 1, title: "A", projectTitle: "NLP").focusSummary(at: wednesdayMorningInBogota) == "NLP")
        #expect(TodayItem(id: 1, title: "A", deadline: deadline("fri 23:59")).focusSummary(at: wednesdayMorningInBogota) == "Due Fri 23:59")
        #expect(TodayItem(id: 1, title: "A").focusSummary(at: wednesdayMorningInBogota) == nil)
    }

    // MARK: Which task the inspector shows

    private let tasks = [
        TodayItem(id: 1, title: "Next one", status: .next),
        TodayItem(id: 2, title: "The Now task", status: .now),
        TodayItem(id: 3, title: "Later one", status: .later),
    ]

    @Test func theInspectorShowsTheSelectedTask() {
        #expect(TaskInspection.shownTask(selection: 3, in: tasks)?.id == 3)
    }

    @Test func withNothingSelectedTheInspectorShowsNow() {
        #expect(TaskInspection.shownTask(selection: nil, in: tasks)?.id == 2)
    }

    @Test func aSelectedTaskThatLeftTheListFallsBackToNow() {
        #expect(TaskInspection.shownTask(selection: 42, in: tasks)?.id == 2)
    }

    @Test func withNoNowTheInspectorShowsTheFirstTask() {
        #expect(TaskInspection.shownTask(selection: nil, in: tasks.filter { $0.status != .now })?.id == 1)
        #expect(TaskInspection.shownTask(selection: nil, in: []) == nil)
    }

    // MARK: Workspace row

    private let server = HerdrServer(sessionName: "s", socketPath: "/s", startedAt: wednesdayMorningInBogota)

    private func folder(_ id: Int64, _ check: FolderCheck) -> ResourceStatus {
        let bookmark = FolderBookmark(data: Data(), path: "/old", inode: 1, volumeUUID: nil, root: nil)
        return ResourceStatus(resource: ContextResource(id: id, owner: .task(1), target: .folder(bookmark), launchOrder: nil,
                                                        createdAt: wednesdayMorningInBogota),
                              isFromProject: false, folder: check)
    }

    @Test func theWorkspaceIsTheHerdrWorkspaceFolder() {
        let link = HerdrLink(server: server, workspaceID: "w1", label: "PhD", cwd: "/Users/me/PhD/applications")

        #expect(TaskInspection.workspace(herdr: link, resources: [folder(1, .healthy(path: "/Users/me/other"))], home: "/Users/me")
            == "~/PhD/applications")
    }

    @Test func withoutAHerdrFolderTheWorkspaceIsTheFirstLinkedFolderThatCanBeFound() {
        let link = HerdrLink(server: server, workspaceID: "w1", label: "PhD", cwd: nil)
        let resources = [folder(1, .needsRepair(.missing)), folder(2, .healthy(path: "/Users/me/nlp"))]

        #expect(TaskInspection.workspace(herdr: link, resources: resources, home: "/Users/me") == "~/nlp")
    }

    @Test func withNoFolderThereIsNoWorkspace() {
        #expect(TaskInspection.workspace(herdr: nil, resources: [], home: "/Users/me") == nil)
    }

    // MARK: Agent card status

    private func live(_ status: HerdrAgentStatus) -> AgentLinkState {
        .live(HerdrAgent(paneID: "p", workspaceID: "w", tabID: "t", name: nil, kind: "claude", status: status, title: nil))
    }

    @Test(arguments: [
        (HerdrAgentStatus.working, "Working", AgentCardStatus.Tone.accent),
        (.blocked, "Needs approval", .amber),
        (.idle, "Ready", .green),
        (.done, "Ready", .green),
        (.unknown, "Unknown", .unknown),
    ])
    func aLiveAgentShowsItsStatus(status: HerdrAgentStatus, title: String, tone: AgentCardStatus.Tone) {
        #expect(AgentCardStatus(live(status), pending: []) == AgentCardStatus(title: title, tone: tone))
    }

    @Test func anUnreviewedResultReadsResultsReady() {
        #expect(AgentCardStatus(live(.idle), pending: [.finished]) == AgentCardStatus(title: "Results ready", tone: .green))
    }

    @Test func aWaitingApprovalOutranksAResult() {
        #expect(AgentCardStatus(live(.idle), pending: [.finished, .approval]).title == "Needs approval")
    }

    @Test func anAgentThatCannotBeSeenSaysSoEvenWithAResultWaiting() {
        #expect(AgentCardStatus(.notFound, pending: [.finished]) == AgentCardStatus(title: "Not found in Herdr", tone: .amber))
        #expect(AgentCardStatus(.unknown, pending: []) == AgentCardStatus(title: "Herdr unavailable", tone: .unknown))
    }

    // MARK: Done

    @Test func doneOnTheNowTaskPromotesTheFirstNextTask() async throws {
        let repository = try TaskRepository(location: StorageLocation(directory: makeTemporaryDirectory()))
        let coordinator = FocusCoordinator(repository: repository)
        try await coordinator.capture(NewTask(title: "First"))
        try await coordinator.capture(NewTask(title: "Second"))
        let first = try await coordinator.todayTasks().first { $0.title == "First" }!
        try await coordinator.moveTask(first.id, to: .now, .top)

        try await coordinator.completeTask(first.id)

        let remaining = try await coordinator.todayTasks()
        #expect(remaining.map(\.title) == ["Second"])
        #expect(remaining[0].status == .now)
    }

    @Test func doneOnAnotherTaskLeavesNowAlone() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.capture(NewTask(title: "Other"))
        let other = try await fixture.coordinator.todayTasks().first { $0.title == "Other" }!

        try await fixture.coordinator.completeTask(other.id)

        #expect(try await fixture.coordinator.todayTasks().map(\.title) == ["Explain baseline results"])
        #expect(await fixture.coordinator.snapshot().currentTaskTitle == "Explain baseline results")
    }

    @Test func doneIsRefusedWhileASessionRunsOnTheTask() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)
        let id = try #require(await fixture.coordinator.snapshot().activeSession?.taskID)

        await #expect(throws: FocusCoordinator.SessionError.sessionStillActive) {
            try await fixture.coordinator.completeTask(id)
        }
        #expect(try await fixture.coordinator.todayTasks().map(\.id) == [id])
    }
}
