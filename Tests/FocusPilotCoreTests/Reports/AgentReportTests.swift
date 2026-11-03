import Foundation
import Testing
@testable import FocusPilotCore

private let target = agent(.idle, pane: "w4:p2", name: "ablation")
private let helper = agent(.working, pane: "w4:pS", name: "second", kind: "claude")
private let caller = HerdrCaller(server: herdrServer, workspaceID: "w4", paneID: "w4:pS")
private let message = "Tests pass. Please open the PR with the title “Fix seeds”."

func report(_ summary: String = "The seed fix passes all 212 tests. Opening the PR is the next step.",
            project: String? = nil, to: String? = "ablation", message: String? = message, from: String? = nil,
            caller: HerdrCaller? = caller, id: UUID = UUID()) -> ReportRequest {
    ReportRequest(id: id, summary: summary, project: project, to: to, message: message, from: from,
                  sentAt: wednesdayMorningInBogota, caller: caller)
}

/// A coordinator on a temporary database, with Herdr faked and project
/// "NLP report" linked to workspace w4.
private struct ReportFixture {
    let repository: TaskRepository
    let herdr = FakeHerdrAgents(.connected(herdrServer, [target, helper]))
    let coordinator: FocusCoordinator

    init() async throws {
        repository = try TaskRepository(location: StorageLocation(directory: makeTemporaryDirectory()),
                                        now: { wednesdayMorningInBogota })
        coordinator = FocusCoordinator(repository: repository, agents: herdr, now: { wednesdayMorningInBogota })
        try await repository.importHerdrWorkspaces([nlpWorkspace], on: herdrServer)
    }

    var prompts: [FakeHerdrAgents.Call] {
        herdr.calls.filter { if case .prompt = $0 { true } else { false } }
    }

    func received(_ request: ReportRequest = report()) async throws -> AgentReport {
        _ = try await coordinator.receiveReport(request)
        return try #require(try await coordinator.reports().first { $0.clientID == request.id })
    }
}

@Suite("Agent reports: receiving")
struct ReportReceivingTests {
    @Test func aReportIsStoredWithItsProjectSourceAndResolvedTarget() async throws {
        let fixture = try await ReportFixture()

        let stored = try await fixture.received()

        #expect(stored.summary == "The seed fix passes all 212 tests. Opening the PR is the next step.")
        #expect(stored.projectTitle == "NLP report")
        #expect(stored.sourceLabel == "second")
        #expect(stored.proposal?.message == message)
        #expect(stored.proposal?.target == ReportTarget(server: herdrServer, paneID: "w4:p2", name: "ablation", kind: "claude"))
        #expect(stored.proposal?.targetProblem == nil)
        #expect(fixture.prompts.isEmpty, "receiving sends nothing")
    }

    @Test func theTargetCanBeGivenByPaneAndTheProjectByName() async throws {
        let fixture = try await ReportFixture()
        try await fixture.repository.importHerdrWorkspaces([thesisWorkspace], on: herdrServer)

        let stored = try await fixture.received(report(project: "thesis", to: "w4:p2", from: "Bowling reviewer"))

        #expect(stored.projectTitle == "Thesis")
        #expect(stored.sourceLabel == "Bowling reviewer")
        #expect(stored.proposal?.target?.paneID == "w4:p2")
    }

    @Test func aReportWithoutAProposalIsJustASummary() async throws {
        let fixture = try await ReportFixture()

        let stored = try await fixture.received(report(to: nil, message: nil))

        #expect(stored.proposal == nil)
    }

    @Test(arguments: [
        ("nobody", "FocusPilot couldn’t find an agent named “nobody” in Herdr when the report arrived."),
        ("w9:p9", "FocusPilot couldn’t find an agent named “w9:p9” in Herdr when the report arrived."),
    ])
    func aTargetThatCannotBeFoundIsKeptWithTheProblem(to: String, problem: String) async throws {
        let fixture = try await ReportFixture()

        let stored = try await fixture.received(report(to: to))

        #expect(stored.proposal?.target == nil)
        #expect(stored.proposal?.targetProblem == problem)
    }

    @Test func twoAgentsWithTheSameNameAreNotGuessedBetween() async throws {
        let fixture = try await ReportFixture()
        fixture.herdr.set(.connected(herdrServer, [target, helper, agent(.idle, pane: "w5:p1", name: "ablation")]))

        let stored = try await fixture.received()

        #expect(stored.proposal?.target == nil)
        #expect(stored.proposal?.targetProblem
            == "More than one agent in Herdr is named “ablation”. Ask for the report again with the pane ID, such as w4:p2.")
    }

    @Test func aReportFromAnotherHerdrServerGetsNoTarget() async throws {
        let fixture = try await ReportFixture()
        let old = HerdrCaller(server: restartedHerdrServer, workspaceID: "w4", paneID: "w4:pS")

        let stored = try await fixture.received(report(caller: old))

        #expect(stored.proposal?.target == nil)
        #expect(stored.proposal?.targetProblem == "The report came from a Herdr session that is no longer running, so its target can’t be trusted.")
    }

    @Test func theSameReportIsStoredOnce() async throws {
        let fixture = try await ReportFixture()
        let request = report()

        _ = try await fixture.coordinator.receiveReport(request)
        let again = try await fixture.coordinator.receiveReport(request)

        #expect(again.wasAlreadyReceived)
        #expect(try await fixture.coordinator.reports().count == 1)
    }

    @Test func reportsSurviveARelaunch() async throws {
        let fixture = try await ReportFixture()
        let request = report()
        _ = try await fixture.coordinator.receiveReport(request)

        let relaunched = FocusCoordinator(repository: fixture.repository, agents: fixture.herdr)

        #expect(try await relaunched.reports().map(\.clientID) == [request.id])
    }
}

@Suite("Agent reports: Accept and Dismiss")
struct ReportAcceptTests {
    @Test func acceptSendsExactlyTheShownTextOnceAndClearsTheReport() async throws {
        let fixture = try await ReportFixture()
        let stored = try await fixture.received()

        #expect(await fixture.coordinator.acceptReport(stored.id, shownMessage: message) == .sent(to: "ablation"))

        #expect(fixture.prompts == [.prompt("w4:p2", message)])
        #expect(try await fixture.coordinator.reports().isEmpty)
        #expect(await fixture.coordinator.acceptReport(stored.id, shownMessage: message) == .notSent(.alreadyHandled))
        #expect(fixture.prompts.count == 1)
    }

    @Test func textThatIsNotWhatWasShownIsNeverSent() async throws {
        let fixture = try await ReportFixture()
        let stored = try await fixture.received()

        #expect(await fixture.coordinator.acceptReport(stored.id, shownMessage: message + " ") == .notSent(.changed))
        #expect(fixture.prompts.isEmpty)
    }

    @Test(arguments: [
        ([helper], AcceptRefusal.gone(name: "ablation")),
        ([agent(.idle, pane: "w4:p2", name: "plots"), helper], .renamed(from: "ablation", to: "plots")),
        ([agent(.idle, pane: "w4:p2", name: "ablation", kind: "codex"), helper], .replaced(name: "ablation")),
        ([agent(.blocked, pane: "w4:p2", name: "ablation"), helper], .blocked(name: "ablation")),
    ])
    func aTargetThatChangedGetsNothing(current: [HerdrAgent], refusal: AcceptRefusal) async throws {
        let fixture = try await ReportFixture()
        let stored = try await fixture.received()
        fixture.herdr.set(.connected(herdrServer, current))

        #expect(await fixture.coordinator.acceptReport(stored.id, shownMessage: message) == .notSent(refusal))
        #expect(fixture.prompts.isEmpty)
        #expect(try await fixture.coordinator.reports().count == 1, "the report stays")
    }

    @Test func aRestartedOrUnreachableHerdrGetsNothing() async throws {
        let fixture = try await ReportFixture()
        let stored = try await fixture.received()

        fixture.herdr.set(.connected(restartedHerdrServer, [target, helper]))
        #expect(await fixture.coordinator.acceptReport(stored.id, shownMessage: message) == .notSent(.gone(name: "ablation")))
        fixture.herdr.set(.disconnected(.notRunning))
        #expect(await fixture.coordinator.acceptReport(stored.id, shownMessage: message) == .notSent(.herdrUnavailable))
        #expect(fixture.prompts.isEmpty)
    }

    @Test func herdrsOwnRefusalIsReportedAndTheReportStays() async throws {
        let fixture = try await ReportFixture()
        let stored = try await fixture.received()
        fixture.herdr.promptResult = .blocked

        #expect(await fixture.coordinator.acceptReport(stored.id, shownMessage: message) == .notSent(.blocked(name: "ablation")))
        #expect(try await fixture.coordinator.reports().count == 1)
    }

    @Test func aProposalWithoutATargetCannotBeAccepted() async throws {
        let fixture = try await ReportFixture()
        let stored = try await fixture.received(report(to: "nobody"))

        #expect(await fixture.coordinator.acceptReport(stored.id, shownMessage: message) == .notSent(.noTarget))
        #expect(fixture.prompts.isEmpty)
    }

    @Test func dismissDiscardsTheReportAndSendsNothing() async throws {
        let fixture = try await ReportFixture()
        let stored = try await fixture.received()

        try await fixture.coordinator.dismissReport(stored.id)

        #expect(try await fixture.coordinator.reports().isEmpty)
        #expect(fixture.prompts.isEmpty)
    }
}

@Suite("Agent reports: what may be sent")
struct ReportRulesTests {
    @Test(arguments: [
        ("", "A report needs a summary."),
        (String(repeating: "a", count: 2_001), "The summary is longer than 2000 characters."),
        ("Done\u{1B}[2J", "The summary has control or text-direction characters, which can’t be shown as typed."),
        ("Done \u{202E}gnp.exe", "The summary has control or text-direction characters, which can’t be shown as typed."),
    ])
    func summariesThatCannotBeShownAsTypedAreRefused(summary: String, problem: String) {
        #expect(report(summary).problem == problem)
    }

    @Test(arguments: [
        ("--wait", "The proposed message can’t start with “-”: Herdr would read it as an option."),
        ("ok\u{3}", "The proposed message has control or text-direction characters, so it can’t be sent exactly as shown."),
        (String(repeating: "a", count: 4_001), "The proposed message is longer than 4000 characters."),
        ("   ", "The proposed message is empty."),
    ])
    func messagesThatCouldBeSentDifferentlyAreRefused(text: String, problem: String) {
        #expect(report(message: text).problem == problem)
    }

    @Test func aMessageNeedsATargetAndATargetNeedsAMessage() {
        #expect(report(to: nil).problem == "A proposed message needs --to, the Herdr agent to send it to.")
        #expect(report(message: nil).problem == "--to needs --message, the exact text to send.")
    }

    @Test func plainTextWithLinesTabsQuotesAndEmojiIsFine() {
        #expect(report("Done.\n\tTable 3 ✅ “ready”", message: "Line one\nLine two\t✅").problem == nil)
    }
}
