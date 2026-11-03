import Foundation
import Testing
@testable import FocusPilotCore

/// Takes reports and records them, standing in for the coordinator.
private actor RecordingReports: ReportSink {
    private(set) var received: [ReportRequest] = []

    func receiveReport(_ request: ReportRequest) async throws -> ReportReceipt {
        received.append(request)
        return ReportReceipt(wasAlreadyReceived: false, projectTitle: "NLP report", targetProblem: nil)
    }
}

@Suite("Command service: reports")
struct ReportServiceTests {
    private let sink = RecordingReports()
    private let service: CommandService

    init() throws {
        let repository = try TaskRepository(location: StorageLocation(directory: makeTemporaryDirectory()),
                                            now: { wednesdayMorningInBogota })
        service = CommandService(repository: repository, reports: sink, now: { wednesdayMorningInBogota })
    }

    @Test func aReportIsHandedOnAndAnswered() async {
        let request = report()

        #expect(await service.handle(.report(request))
            == .reported(ReportReceipt(wasAlreadyReceived: false, projectTitle: "NLP report", targetProblem: nil)))
        #expect(await sink.received == [request])
    }

    @Test func aReportThatBreaksTheRulesIsRefusedAndNotStored() async {
        #expect(await service.handle(.report(report(message: "--wait")))
            == .refused("The proposed message can’t start with “-”: Herdr would read it as an option."))
        #expect(await sink.received.isEmpty)
    }

    @Test func aBurstFromOnePaneIsRefusedAndAddsKeepTheirOwnBudget() async {
        for _ in 0..<20 { _ = await service.handle(.report(report())) }

        #expect(await service.handle(.report(report())) == .refused(CommandService.reportRateLimitMessage))
        #expect(await sink.received.count == 20)
        guard case .added = await service.handle(.add(herdrAdd("Still fine", from: caller))) else {
            Issue.record("an add was refused by the report budget")
            return
        }
    }

    @Test func withoutTheAppsReportHandlingReportsAreRefused() async throws {
        let repository = try TaskRepository(location: StorageLocation(directory: makeTemporaryDirectory()))
        let bare = CommandService(repository: repository)

        #expect(await bare.handle(.report(report())) == .refused("FocusPilot can’t take reports right now."))
    }
}

private let caller = HerdrCaller(server: herdrServer, workspaceID: "w4", paneID: "w4:pS")

@Suite("Inbox: reports")
struct ReportInboxTests {
    private let inbox: TaskInbox

    init() throws {
        inbox = TaskInbox(directory: try makeTemporaryDirectory().appending(path: "CommandLine"))
    }

    private func drain() async throws -> (adds: [String], reports: [UUID], imported: Int) {
        let adds = Box<[String]>([]), reports = Box<[UUID]>([])
        let drained = try await inbox.drain(isPermanent: { _ in false }, reports: { reports.append($0.id) }) { adds.append($0.text) }
        return (adds.value, reports.value, drained.imported)
    }

    @Test func queuedAddsAndReportsAreImportedInOrder() async throws {
        let first = report(), second = report()
        try inbox.enqueue(herdrAdd("Reply to co-advisor"))
        try inbox.enqueue(first)
        try inbox.enqueue(herdrAdd("Re-run ablation"))
        try inbox.enqueue(second)

        let drained = try await drain()

        #expect(drained.adds == ["Reply to co-advisor", "Re-run ablation"])
        #expect(drained.reports == [first.id, second.id])
        #expect(drained.imported == 4)
        #expect(try await drain().imported == 0, "each is imported once")
    }

    @Test func aQueuedReportKeepsEveryField() async throws {
        let request = report(project: "NLP report", from: "second")
        try inbox.enqueue(request)
        let got = Box<[ReportRequest]>([])

        _ = try await inbox.drain(isPermanent: { _ in false }, reports: { got.append($0) }) { _ in }

        #expect(got.value == [request])
    }

    @Test func aPaneQueuesAtMostTwentyReportsAMinute() throws {
        for _ in 0..<20 { try inbox.enqueue(report()) }

        #expect(throws: TaskInbox.Refusal.rateLimited) { try inbox.enqueue(report()) }
        try inbox.enqueue(herdrAdd("Adds have their own budget", from: caller))
    }

    @Test func aDrainWithoutReportHandlingLeavesReportsQueued() async throws {
        try inbox.enqueue(herdrAdd("Reply to co-advisor"))
        try inbox.enqueue(report())
        try inbox.enqueue(herdrAdd("Re-run ablation"))
        let adds = Box<[String]>([])

        _ = try await inbox.drain(isPermanent: { _ in false }) { adds.append($0.text) }

        #expect(adds.value == ["Reply to co-advisor"])
        #expect(try await drain().reports.count == 1)
    }
}

/// A value the drain's `@Sendable` closures can fill in.
final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.withLock { stored } }
    func append<Element>(_ element: Element) where Value == [Element] { lock.withLock { stored.append(element) } }
}

/// `focuspilot report` end to end, through a real socket to a coordinator
/// on a temporary database (or to nothing, when the app is "closed").
@Suite("focuspilot report")
final class ReportCLITests {
    private let location: StorageLocation
    private let repository: TaskRepository
    private let herdr = FakeHerdrAgents(.connected(herdrServer, [agent(.idle, pane: "w4:p2", name: "ablation"),
                                                                agent(.working, pane: "w4:pS", name: "second")]))
    private let coordinator: FocusCoordinator
    private var server: CommandSocketServer?
    private let paneEnvironment = ["HOME": "/Users/owner", "HERDR_SOCKET_PATH": herdrServer.socketPath,
                                   "HERDR_WORKSPACE_ID": "w4", "HERDR_PANE_ID": "w4:pS"]

    init() async throws {
        location = StorageLocation(directory: try makeShortDirectory())
        repository = try TaskRepository(location: location, now: { wednesdayMorningInBogota })
        coordinator = FocusCoordinator(repository: repository, agents: herdr, now: { wednesdayMorningInBogota })
        try await repository.importHerdrWorkspaces([nlpWorkspace], on: herdrServer)
    }

    deinit {
        server?.stop()
        try? FileManager.default.removeItem(at: location.directory)
    }

    private func startApp() throws {
        let service = CommandService(repository: repository, reports: coordinator, now: { wednesdayMorningInBogota })
        let server = CommandSocketServer(path: location.commandSocketPath) { await service.handle($0) }
        try server.start()
        self.server = server
    }

    private func run(_ arguments: String...) async -> FocusPilotCommand.Outcome {
        let command = FocusPilotCommand(location: location, environment: paneEnvironment, now: wednesdayMorningInBogota,
                                        timeZone: bogota,
                                        socketCreationDate: { $0.path == herdrServer.socketPath ? herdrServer.startedAt : nil })
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: command.run(arguments)) }
        }
    }

    @Test func aReportWithAProposalReachesTheAttentionQueueAndSendsNothing() async throws {
        try startApp()

        let outcome = await run("report", "--summary", "The seed fix passes all 212 tests.", "--to", "ablation",
                                "--message", "Tests pass. Please open the PR.")

        #expect(outcome.status == 0)
        #expect(outcome.output == """
            Reported to FocusPilot, in NLP report. The owner sees it in Needs you.
            If they accept, FocusPilot sends your message to ablation, exactly as written.

            """)
        let stored = try #require(try await coordinator.reports().first)
        #expect(stored.summary == "The seed fix passes all 212 tests.")
        #expect(stored.sourceLabel == "second")
        #expect(stored.proposal?.message == "Tests pass. Please open the PR.")
        #expect(!herdr.calls.contains { if case .prompt = $0 { true } else { false } })
    }

    @Test func aTargetThatCannotBeFoundIsSaidAtOnce() async throws {
        try startApp()

        let outcome = await run("report", "--summary", "Done.", "--to", "nobody", "--message", "Open the PR.")

        #expect(outcome.status == 0)
        #expect(outcome.output.contains("Note: FocusPilot couldn’t find an agent named “nobody” in Herdr when the report arrived."))
    }

    @Test func aRefusedReportFailsWithTheReason() async throws {
        try startApp()

        let outcome = await run("report", "--summary", "Done.", "--to", "ablation", "--message", "--wait")

        #expect(outcome.status == 1)
        #expect(outcome.error == "Refused: The proposed message can’t start with “-”: Herdr would read it as an option.\n")
        #expect(try await coordinator.reports().isEmpty)
    }

    @Test(arguments: [["report"], ["report", "--summary"], ["report", "--summary", "x", "--bogus", "y"], ["report", "loose words"]])
    func usageErrorsPrintTheUsage(_ arguments: [String]) async {
        let command = FocusPilotCommand(location: location, environment: paneEnvironment, now: wednesdayMorningInBogota, timeZone: bogota)
        let outcome = command.run(arguments)

        #expect(outcome.status == 2)
        #expect(outcome.error.contains("focuspilot report"))
    }

    @Test func whenFocusPilotIsClosedTheReportIsQueued() async throws {
        let outcome = await run("report", "--json", "--summary", "Done.", "--from", "Bowling reviewer")

        #expect(outcome.status == 0)
        let json = try JSONSerialization.jsonObject(with: Data(outcome.output.utf8)) as? [String: Any]
        #expect(json?["status"] as? String == "queued")
        let got = Box<[ReportRequest]>([])
        _ = try await location.inbox.drain(isPermanent: { _ in false }, reports: { got.append($0) }) { _ in }
        #expect(got.value.map(\.from) == ["Bowling reviewer"])
    }

    @Test func jsonOutputIsMachineReadable() async throws {
        try startApp()

        let outcome = await run("report", "--json", "--summary", "Done.", "--to", "ablation", "--message", "Open the PR.")

        let json = try JSONSerialization.jsonObject(with: Data(outcome.output.utf8)) as? [String: Any]
        #expect(json?["status"] as? String == "reported")
        #expect(json?["project"] as? String == "NLP report")
        #expect(json?["targetProblem"] is NSNull)
    }
}
