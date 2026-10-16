import Foundation
import Testing
@testable import FocusPilotCore

/// The focuspilot CLI end to end: arguments and Herdr environment in, text
/// out, through a real socket to a `CommandService` (or to nothing, when the
/// app is "closed").
@Suite("focuspilot command")
final class FocusPilotCommandTests {
    private let location: StorageLocation
    private let repository: TaskRepository
    private var server: CommandSocketServer?

    /// What a Herdr pane in workspace w4 exports.
    private let paneEnvironment = [
        "HOME": "/Users/owner",
        "HERDR_SOCKET_PATH": herdrServer.socketPath,
        "HERDR_WORKSPACE_ID": "w4",
        "HERDR_PANE_ID": "w4:p2",
    ]

    init() throws {
        location = StorageLocation(directory: try makeShortDirectory())
        repository = try TaskRepository(location: location, now: { wednesdayMorningInBogota })
    }

    deinit {
        server?.stop()
        try? FileManager.default.removeItem(at: location.directory)
    }

    private func startApp() throws {
        let service = CommandService(repository: repository, now: { wednesdayMorningInBogota })
        let server = CommandSocketServer(path: location.commandSocketPath) { await service.handle($0) }
        try server.start()
        self.server = server
    }

    /// Runs the command on a dispatch queue, as the real CLI blocks its own
    /// main thread: blocking a Swift concurrency thread would starve the
    /// in-process server that has to answer.
    private func run(_ arguments: String..., environment: [String: String]? = nil) async -> FocusPilotCommand.Outcome {
        let command = FocusPilotCommand(location: location, environment: environment ?? paneEnvironment,
                                        now: wednesdayMorningInBogota, timeZone: bogota,
                                        socketCreationDate: { $0.path == herdrServer.socketPath ? herdrServer.startedAt : nil })
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: command.run(arguments)) }
        }
    }

    private func linkNLPReport() async throws {
        try await repository.importHerdrWorkspaces([nlpWorkspace], on: herdrServer)
    }

    // MARK: add

    @Test func addFilesTheTaskInTheWorkspacesProject() async throws {
        try startApp()
        try await linkNLPReport()

        let outcome = await run("add", "Re-run ablation by fri 23:59")

        #expect(outcome.status == 0)
        #expect(outcome.output == """
            Added “Re-run ablation” to the end of Next in NLP report, marked from Herdr.
            Deadline: Fri 16 Oct 2026, 23:59 · America/Bogota (GMT−5)

            """)
        let task = try #require(try await repository.todayTasks().first)
        #expect(task.projectTitle == "NLP report")
        #expect(task.isFromHerdr)
        #expect(try await repository.herdrSource(of: task.id) == "w4:p2")
    }

    @Test func wordsAfterAddAreJoined() async throws {
        try startApp()
        _ = await run("add", "Reply", "to", "co-advisor")
        #expect(try await repository.tasks().map(\.title) == ["Reply to co-advisor"])
    }

    @Test func aWorkspaceWithoutAProjectIsToldSo() async throws {
        try startApp()
        #expect(await run("add", "Reply to co-advisor").output == """
            Added “Reply to co-advisor” to the end of Next under No project, marked from Herdr.
            This Herdr workspace has no linked project in FocusPilot.

            """)
    }

    @Test func outsideHerdrTheTaskGoesToNoProject() async throws {
        try startApp()
        try await linkNLPReport()

        let outcome = await run("add", "Renew library access", environment: ["HOME": "/Users/owner"])

        #expect(outcome.output == """
            Added “Renew library access” to the end of Next under No project, marked from Herdr.
            Not run from a Herdr pane, so no project was chosen.

            """)
        #expect(try await repository.todayTasks().first?.projectTitle == nil)
    }

    @Test func anUnreadableDeadlineIsAddedWithoutOneAndHinted() async throws {
        try startApp()
        #expect(await run("add", "Submit form by Feb 30").output == """
            Added “Submit form by Feb 30” to the end of Next under No project, marked from Herdr.
            This Herdr workspace has no linked project in FocusPilot.
            Note: Could not read this deadline. Try “fri 23:59”, “Oct 20” or “2026-10-20”.

            """)
    }

    @Test func theRateLimitRefusalIsPrintedAndFails() async throws {
        try startApp()
        for index in 0..<20 { _ = await run("add", "Task \(index)") }

        let outcome = await run("add", "One too many")

        #expect(outcome.status == 1)
        #expect(outcome.output.isEmpty)
        #expect(outcome.error == CommandService.rateLimitMessage + "\n")
    }

    @Test func addWithJSONIsMachineReadable() async throws {
        try startApp()
        try await linkNLPReport()

        let outcome = await run("add", "--json", "Re-run ablation by fri 23:59")

        let json = try JSONSerialization.jsonObject(with: Data(outcome.output.utf8)) as? [String: Any]
        #expect(json?["status"] as? String == "added")
        #expect(json?["title"] as? String == "Re-run ablation")
        #expect(json?["project"] as? String == "NLP report")
        #expect(json?["deadline"] as? String == "Fri 16 Oct 2026, 23:59 · America/Bogota (GMT−5)")
    }

    @Test func aBlankAddIsAUsageError() async {
        let outcome = await run("add", "  ")
        #expect(outcome.status == 2)
        #expect(outcome.error.contains("Nothing to add"))
    }

    // MARK: App closed

    @Test func withTheAppClosedTheAddIsQueuedAndImportedLater() async throws {
        let outcome = await run("add", "Reply to co-advisor")

        #expect(outcome.status == 0)
        #expect(outcome.output == """
            FocusPilot is not running. Queued “Reply to co-advisor”; it will be added when FocusPilot starts.

            """)
        #expect(try await repository.tasks().isEmpty)

        let repository = repository
        #expect(try await location.inbox.drain { _ = try await repository.addFromHerdr($0) } == 1)
        #expect(try await repository.tasks().map(\.title) == ["Reply to co-advisor"])
    }

    @Test func aBurstIsRefusedEvenWhileQueued() async {
        for index in 0..<20 { _ = await run("add", "Task \(index)") }
        let outcome = await run("add", "One too many")
        #expect(outcome.status == 1)
        #expect(outcome.error == CommandService.rateLimitMessage + "\n")
    }

    @Test func tasksSaysHonestlyThatTheAppIsNotRunning() async {
        let outcome = await run("tasks")
        #expect(outcome.status == 3)
        #expect(outcome.error == "FocusPilot is not running, so tasks can’t be read.\n")
        #expect(await run("tasks", "--json").output == "{\"running\":false}\n")
    }

    // MARK: tasks

    @Test func tasksListsNowAndTheWorkspacesProject() async throws {
        try startApp()
        try await linkNLPReport()
        let now = try await repository.addTask(NewTask(title: "PhD shortlist", projectName: "Applications",
                                                       nextAction: "Open the spreadsheet"))
        try await repository.moveTask(now.id!, to: .now, .top)
        _ = try await repository.addTask(NewTask(title: "Explain baseline", projectName: "NLP report"))
        _ = await run("add", "Re-run ablation by fri 23:59")
        _ = try await repository.addTask(NewTask(title: "Renew library access"))

        #expect(await run("tasks").output == """
            Now: PhD shortlist
              Next action: Open the spreadsheet

            NLP report (this workspace’s project)
              Next   Explain baseline
              Next   Re-run ablation · due Fri 16 Oct 2026, 23:59 · America/Bogota (GMT−5) · from Herdr

            """)
    }

    @Test func outsideHerdrTasksListsOnlyNow() async throws {
        try startApp()
        _ = try await repository.addTask(NewTask(title: "Renew library access"))

        #expect(await run("tasks", environment: ["HOME": "/Users/owner"]).output == """
            Now: nothing pinned

            Not run from a Herdr pane, so only Now is shown.

            """)
    }

    @Test func tasksWithJSONIsMachineReadable() async throws {
        try startApp()
        try await linkNLPReport()
        _ = await run("add", "Re-run ablation")

        let json = try JSONSerialization.jsonObject(with: Data(await run("tasks", "--json").output.utf8)) as? [String: Any]

        #expect(json?["running"] as? Bool == true)
        #expect(json?["project"] as? String == "NLP report")
        #expect(json?.keys.contains("now") == true)
        let tasks = json?["tasks"] as? [[String: Any]]
        #expect(tasks?.first?["title"] as? String == "Re-run ablation")
        #expect(tasks?.first?["status"] as? String == "next")
        #expect(tasks?.first?["fromHerdr"] as? Bool == true)
    }

    // MARK: Usage

    @Test func unknownCommandsPrintUsage() async {
        let outcome = await run("delete", "everything")
        #expect(outcome.status == 2)
        #expect(outcome.error.hasPrefix("Usage:"))
        #expect(await run().status == 2)
    }

    @Test func helpPrintsUsage() async {
        let outcome = await run("help")
        #expect(outcome.status == 0)
        #expect(outcome.output.hasPrefix("Usage:"))
    }
}
