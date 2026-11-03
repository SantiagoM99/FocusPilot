import Foundation
import GRDB
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
    let location: StorageLocation
    let repository: TaskRepository
    let herdr = FakeHerdrAgents(.connected(herdrServer, [target, helper]))
    let coordinator: FocusCoordinator

    init() async throws {
        location = StorageLocation(directory: try makeTemporaryDirectory())
        repository = try TaskRepository(location: location, now: { wednesdayMorningInBogota })
        coordinator = FocusCoordinator(repository: repository, agents: herdr, now: { wednesdayMorningInBogota })
        try await repository.importHerdrWorkspaces([nlpWorkspace], on: herdrServer)
    }

    /// Makes recording a send fail, as a full disk would, after Herdr took the message.
    func breakSentRecording() throws {
        try DatabaseQueue(path: location.ownerDatabaseURL.path).write { db in
            try db.execute(sql: """
                CREATE TRIGGER failSent BEFORE UPDATE OF sentAt ON agentReport
                BEGIN SELECT RAISE(ABORT, 'disk full'); END
                """)
        }
    }

    func restoreSentRecording() {
        try? DatabaseQueue(path: location.ownerDatabaseURL.path).write { db in try db.execute(sql: "DROP TRIGGER failSent") }
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
        #expect(stored.sourceLabel == "second")
        #expect(stored.claimedName == "Bowling reviewer")
        #expect(stored.proposal?.target?.paneID == "w4:p2")
    }

    // #68 review: --from is free text, so it never replaces the pane's real
    // Herdr name; it is shown only as what the sender calls itself.
    @Test func aSenderCannotTakeAnotherAgentsName() async throws {
        let fixture = try await ReportFixture()

        let stored = try await fixture.received(report(from: "ablation"))

        #expect(stored.sourceLabel == "second")
        #expect(stored.claimedName == "ablation")
    }

    @Test func aPaneHerdrDoesNotKnowIsNamedByItsPane() async throws {
        let fixture = try await ReportFixture()
        let stranger = HerdrCaller(server: herdrServer, workspaceID: "w4", paneID: "w4:pZ")

        #expect(try await fixture.received(report(caller: stranger)).sourceLabel == "w4:pZ")
        #expect(try await fixture.received(report(from: "second", caller: nil)).sourceLabel == "An agent outside Herdr")
    }

    @Test func aReportWithoutAProposalIsJustASummary() async throws {
        let fixture = try await ReportFixture()

        let stored = try await fixture.received(report(to: nil, message: nil))

        #expect(stored.proposal == nil)
    }

    @Test(arguments: [
        ("nobody", "“nobody” not found in Herdr"),
        ("w9:p9", "“w9:p9” not found in Herdr"),
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
            == "Several agents are named “ablation”")
    }

    @Test func aReportFromAnotherHerdrServerGetsNoTarget() async throws {
        let fixture = try await ReportFixture()
        let old = HerdrCaller(server: restartedHerdrServer, workspaceID: "w4", paneID: "w4:pS")

        let stored = try await fixture.received(report(caller: old))

        #expect(stored.proposal?.target == nil)
        #expect(stored.proposal?.targetProblem == "From a Herdr session that has ended")
    }

    @Test func theSameReportIsStoredOnce() async throws {
        let fixture = try await ReportFixture()
        let request = report()

        _ = try await fixture.coordinator.receiveReport(request)
        let again = try await fixture.coordinator.receiveReport(request)

        #expect(again.wasAlreadyReceived)
        #expect(try await fixture.coordinator.reports().count == 1)
    }

    // #68 review: the app's limit holds for queued reports too, even ones
    // written into the inbox without the CLI's own check.
    @Test func importingTheInboxKeepsTheRateLimit() async throws {
        let fixture = try await ReportFixture()
        let inbox = fixture.location.inbox
        try FileManager.default.createDirectory(at: inbox.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lines = try (0..<25).map { _ in String(decoding: try JSONEncoder().encode(ReportLine(report: report())), as: UTF8.self) }
        try (lines.joined(separator: "\n") + "\n").write(to: inbox.fileURL, atomically: true, encoding: .utf8)

        _ = try await fixture.coordinator.importInbox(inbox)

        #expect(try await fixture.coordinator.reports().count == 20)
    }

    // Decision 0003 (2026-11-03): the row reports state only.
    @Test func refusalsAreShortStatusLines() {
        #expect(AcceptRefusal.blocked(name: "ablation").text == "Not sent: ablation is waiting for an approval")
        #expect(AcceptRefusal.gone(name: "ablation").text == "Not sent: ablation isn’t in Herdr")
        #expect(AcceptRefusal.renamed(from: "ablation", to: "plots").text == "Not sent: ablation is now named “plots”")
        #expect(AcceptRefusal.replaced(name: "ablation").text == "Not sent: a different program is in ablation’s pane")
        #expect(AcceptRefusal.herdrUnavailable.text == "Not sent: Herdr isn’t reachable")
        #expect(AcceptRefusal.changed.text == "Not sent: the report changed after it was shown")
        #expect(AcceptRefusal.outcomeUnknown(name: "ablation").text == "Outcome unknown: ablation may have the message")
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

        #expect(await fixture.coordinator.acceptReport(stored.id, shownMessage: message, shownTarget: stored.proposal?.target)
            == .sent(to: "ablation"))

        #expect(fixture.prompts == [.prompt("w4:p2", message)])
        #expect(try await fixture.coordinator.reports().isEmpty)
        #expect(await fixture.coordinator.acceptReport(stored.id, shownMessage: message, shownTarget: stored.proposal?.target) == .notSent(.alreadyHandled))
        #expect(fixture.prompts.count == 1)
    }

    @Test func textThatIsNotWhatWasShownIsNeverSent() async throws {
        let fixture = try await ReportFixture()
        let stored = try await fixture.received()

        #expect(await fixture.coordinator.acceptReport(stored.id, shownMessage: message + " ", shownTarget: stored.proposal?.target) == .notSent(.changed))
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

        #expect(await fixture.coordinator.acceptReport(stored.id, shownMessage: message, shownTarget: stored.proposal?.target) == .notSent(refusal))
        #expect(fixture.prompts.isEmpty)
        #expect(try await fixture.coordinator.reports().count == 1, "the report stays")
    }

    @Test func aRestartedOrUnreachableHerdrGetsNothing() async throws {
        let fixture = try await ReportFixture()
        let stored = try await fixture.received()

        fixture.herdr.set(.connected(restartedHerdrServer, [target, helper]))
        #expect(await fixture.coordinator.acceptReport(stored.id, shownMessage: message, shownTarget: stored.proposal?.target) == .notSent(.gone(name: "ablation")))
        fixture.herdr.set(.disconnected(.notRunning))
        #expect(await fixture.coordinator.acceptReport(stored.id, shownMessage: message, shownTarget: stored.proposal?.target) == .notSent(.herdrUnavailable))
        #expect(fixture.prompts.isEmpty)
    }

    @Test func herdrsOwnRefusalIsReportedAndTheReportStays() async throws {
        let fixture = try await ReportFixture()
        let stored = try await fixture.received()
        fixture.herdr.promptResult = .blocked

        #expect(await fixture.coordinator.acceptReport(stored.id, shownMessage: message, shownTarget: stored.proposal?.target) == .notSent(.blocked(name: "ablation")))
        #expect(try await fixture.coordinator.reports().count == 1)
    }

    @Test func aProposalWithoutATargetCannotBeAccepted() async throws {
        let fixture = try await ReportFixture()
        let stored = try await fixture.received(report(to: "nobody"))

        #expect(await fixture.coordinator.acceptReport(stored.id, shownMessage: message, shownTarget: stored.proposal?.target) == .notSent(.noTarget))
        #expect(fixture.prompts.isEmpty)
    }

    @Test func aTargetOtherThanTheOneShownIsNeverSentTo() async throws {
        let fixture = try await ReportFixture()
        let stored = try await fixture.received()
        let other = ReportTarget(server: herdrServer, paneID: "w4:pS", name: "second", kind: "claude")

        #expect(await fixture.coordinator.acceptReport(stored.id, shownMessage: message, shownTarget: other) == .notSent(.changed))
        #expect(fixture.prompts.isEmpty)
    }

    // #68 review: once Herdr may have the message, the report is never
    // accepted again; the owner checks the agent and can only dismiss.
    @Test(arguments: [PromptResult.unknown])
    func anUnknownOutcomeLocksTheReport(_ result: PromptResult) async throws {
        let fixture = try await ReportFixture()
        let stored = try await fixture.received()
        fixture.herdr.promptResult = result

        #expect(await fixture.coordinator.acceptReport(stored.id, shownMessage: message, shownTarget: stored.proposal?.target)
            == .outcomeUnknown(to: "ablation"))
        fixture.herdr.promptResult = .sent
        let after = try #require(try await fixture.coordinator.reports().first)
        #expect(after.outcomeUnknown)
        #expect(await fixture.coordinator.acceptReport(stored.id, shownMessage: message, shownTarget: stored.proposal?.target)
            == .notSent(.outcomeUnknown(name: "ablation")))
        #expect(fixture.prompts.count == 1)

        try await fixture.coordinator.dismissReport(stored.id)
        #expect(try await fixture.coordinator.reports().isEmpty)
    }

    @Test func aSendThatCannotBeRecordedLocksTheReportToo() async throws {
        let fixture = try await ReportFixture()
        let stored = try await fixture.received()
        fixture.herdr.beforePromptReturns = { try? fixture.breakSentRecording() }

        #expect(await fixture.coordinator.acceptReport(stored.id, shownMessage: message, shownTarget: stored.proposal?.target)
            == .outcomeUnknown(to: "ablation"))
        fixture.restoreSentRecording()
        #expect(try await fixture.coordinator.reports().first?.outcomeUnknown == true)
        #expect(await fixture.coordinator.acceptReport(stored.id, shownMessage: message, shownTarget: stored.proposal?.target)
            == .notSent(.outcomeUnknown(name: "ablation")))
        #expect(fixture.prompts.count == 1)
    }

    @Test func aDefiniteRefusalLeavesTheReportAcceptable() async throws {
        let fixture = try await ReportFixture()
        let stored = try await fixture.received()
        fixture.herdr.promptResult = .blocked
        _ = await fixture.coordinator.acceptReport(stored.id, shownMessage: message, shownTarget: stored.proposal?.target)

        fixture.herdr.promptResult = .sent
        #expect(await fixture.coordinator.acceptReport(stored.id, shownMessage: message, shownTarget: stored.proposal?.target)
            == .sent(to: "ablation"))
    }

    // #68 review: an agent without a name is matched by server start, pane
    // and program; anything new about it is doubt, and doubt sends nothing.
    @Test func aNamelessAgentThatGainedANameGetsNothing() async throws {
        let fixture = try await ReportFixture()
        let nameless = agent(.idle, pane: "w4:p7", name: nil)
        fixture.herdr.set(.connected(herdrServer, [target, helper, nameless]))
        let stored = try await fixture.received(report(to: "w4:p7"))
        #expect(stored.proposal?.target == ReportTarget(server: herdrServer, paneID: "w4:p7", name: nil, kind: "claude"))

        fixture.herdr.set(.connected(herdrServer, [target, helper, agent(.idle, pane: "w4:p7", name: "new-one")]))

        #expect(await fixture.coordinator.acceptReport(stored.id, shownMessage: message, shownTarget: stored.proposal?.target)
            == .notSent(.renamed(from: "w4:p7", to: "new-one")))
        #expect(fixture.prompts.isEmpty)
    }

    @Test func aNamelessAgentThatIsUnchangedCanBeSentTo() async throws {
        let fixture = try await ReportFixture()
        fixture.herdr.set(.connected(herdrServer, [target, helper, agent(.idle, pane: "w4:p7", name: nil)]))
        let stored = try await fixture.received(report(to: "w4:p7"))

        #expect(await fixture.coordinator.acceptReport(stored.id, shownMessage: message, shownTarget: stored.proposal?.target)
            == .sent(to: "w4:p7"))
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
        ("Done\u{1B}[2J", "The summary has control, invisible or text-direction characters, which can’t be shown as typed."),
        ("Done \u{202E}gnp.exe", "The summary has control, invisible or text-direction characters, which can’t be shown as typed."),
    ])
    func summariesThatCannotBeShownAsTypedAreRefused(summary: String, problem: String) {
        #expect(report(summary).problem == problem)
    }

    @Test(arguments: [
        ("--wait", "The proposed message can’t start with “-”: Herdr would read it as an option."),
        ("ok\u{3}", "The proposed message has control, invisible or text-direction characters, so it can’t be sent exactly as shown."),
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

    // #68 review: nothing invisible reaches the agent while the owner sees a
    // harmless sentence. Every format character is refused except the
    // zero-width joiner inside emoji, and so are line and paragraph separators.
    @Test(arguments: ["\u{200B}", "\u{2060}", "\u{FEFF}", "\u{00AD}", "\u{E0041}\u{E0042}", "\u{E007F}", "\u{2028}", "\u{2029}",
                      "\u{200E}", "\u{202E}", "\u{2066}", "\u{061C}", "\u{180E}"])
    func invisibleCharactersAreRefusedEverywhere(_ hidden: String) {
        #expect(report(message: "Open the PR.\(hidden) Then delete main.") .problem
            == "The proposed message has control, invisible or text-direction characters, so it can’t be sent exactly as shown.")
        #expect(report("Done.\(hidden)").problem
            == "The summary has control, invisible or text-direction characters, which can’t be shown as typed.")
        #expect(report(from: "second\(hidden)").problem == "The --from name must be plain text on one line.")
    }

    @Test func theZeroWidthJoinerInsideEmojiIsFine() {
        #expect(report(message: "Family: 👨‍👩‍👧‍👦").problem == nil)
    }

    // A character count alone lets a few long emoji sequences weigh a lot.
    @Test func sizeIsCappedInBytesToo() {
        let family = "👨‍👩‍👧‍👦"
        #expect(report(String(repeating: family, count: 1_000)).problem == "The summary is longer than 8000 bytes.")
        #expect(report(message: String(repeating: family, count: 1_000)).problem == "The proposed message is longer than 16000 bytes.")
        #expect(report(project: String(repeating: family, count: 50)).problem == "The project name is longer than 400 bytes.")
    }

    @Test func plainTextWithLinesTabsQuotesAndEmojiIsFine() {
        #expect(report("Done.\n\tTable 3 ✅ “ready”", message: "Line one\nLine two\t✅").problem == nil)
    }
}
