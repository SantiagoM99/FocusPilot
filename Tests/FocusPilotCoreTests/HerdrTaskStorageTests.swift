import Foundation
import Testing
@testable import FocusPilotCore

let nlpPane = HerdrCaller(server: herdrServer, workspaceID: "w4", paneID: "w4:p2")

/// An add as the CLI sends it, captured on Wednesday morning in Bogotá.
func herdrAdd(_ text: String, from caller: HerdrCaller? = nlpPane, id: UUID = UUID()) -> HerdrAddRequest {
    HerdrAddRequest(id: id, text: text, capturedAt: wednesdayMorningInBogota, timeZone: bogota, caller: caller)
}

@Suite("Tasks added from Herdr")
struct HerdrTaskStorageTests {
    private let repository: TaskRepository

    init() throws {
        repository = try TaskRepository(location: StorageLocation(directory: makeTemporaryDirectory()),
                                        now: { wednesdayMorningInBogota })
    }

    private func linkNLPReport() async throws {
        try await repository.importHerdrWorkspaces([nlpWorkspace], on: herdrServer)
    }

    @Test func addGoesToTheEndOfNextInTheWorkspacesProject() async throws {
        try await linkNLPReport()
        _ = try await repository.addTask(NewTask(title: "Explain baseline", projectName: "NLP report"))

        let added = try await repository.addFromHerdr(herdrAdd("Re-run ablation by fri 23:59"))

        #expect(added.projectTitle == "NLP report")
        #expect(added.title == "Re-run ablation")
        let tasks = try await repository.todayTasks()
        #expect(tasks.map(\.title) == ["Explain baseline", "Re-run ablation"])
        #expect(tasks.map(\.status) == [.next, .next])
        #expect(tasks[1].projectTitle == "NLP report")
        #expect(tasks[1].isFromHerdr)
        #expect(!tasks[0].isFromHerdr)
        #expect(tasks[1].deadline == DeadlineParser(now: wednesdayMorningInBogota, timeZone: bogota).parse("by fri 23:59"))
    }

    @Test func addNeverChangesNowOrOtherTasks() async throws {
        try await linkNLPReport()
        let now = try await repository.addTask(NewTask(title: "Explain baseline", projectName: "NLP report"))
        try await repository.moveTask(now.id!, to: .now, .top)
        let before = try await repository.tasks()

        _ = try await repository.addFromHerdr(herdrAdd("Reply to co-advisor"))

        let after = try await repository.tasks()
        #expect(Array(after.prefix(before.count)) == before)
        #expect(try await repository.nowTask()?.title == "Explain baseline")
    }

    @Test func theSameRequestIsAddedOnce() async throws {
        let id = UUID()
        let first = try await repository.addFromHerdr(herdrAdd("Reply to co-advisor", id: id))
        let again = try await repository.addFromHerdr(herdrAdd("Reply to co-advisor", id: id))

        #expect(!first.wasAlreadyAdded)
        #expect(again.wasAlreadyAdded)
        #expect(again.taskID == first.taskID)
        #expect(try await repository.tasks().count == 1)
    }

    @Test func aWorkspaceWithoutAProjectFilesUnderNoProject() async throws {
        let added = try await repository.addFromHerdr(herdrAdd("Reply to co-advisor"))

        #expect(added.projectTitle == nil)
        #expect(added.workspaceHasNoProject)
        #expect(try await repository.todayTasks().first?.projectTitle == nil)
    }

    @Test func outsideHerdrTheTaskFilesUnderNoProject() async throws {
        try await linkNLPReport()
        let added = try await repository.addFromHerdr(herdrAdd("Renew library access", from: nil))

        #expect(added.projectTitle == nil)
        #expect(!added.workspaceHasNoProject)
    }

    @Test func aLinkFromAnEarlierServerDoesNotMatch() async throws {
        try await linkNLPReport()
        let afterRestart = HerdrCaller(server: restartedHerdrServer, workspaceID: "w4", paneID: "w4:p1")

        #expect(try await repository.addFromHerdr(herdrAdd("Reply", from: afterRestart)).projectTitle == nil)
    }

    @Test func anUnreadableDeadlineNeverBlocksTheAdd() async throws {
        let added = try await repository.addFromHerdr(herdrAdd("Submit form by Feb 30"))

        #expect(added.title == "Submit form by Feb 30")
        #expect(added.deadlineDescription == nil)
        #expect(added.hints == ["Could not read this deadline. Try “fri 23:59”, “Oct 20” or “2026-10-20”."])
    }

    @Test func thePaneIsRecorded() async throws {
        let added = try await repository.addFromHerdr(herdrAdd("Reply"))
        #expect(try await repository.herdrSource(of: added.taskID) == "w4:p2")
    }

    // MARK: Undo

    @Test func undoRemovesATaskAddedFromHerdr() async throws {
        let added = try await repository.addFromHerdr(herdrAdd("Reply to co-advisor"))
        try await repository.undoHerdrAdd(added.taskID)
        #expect(try await repository.tasks().isEmpty)
    }

    @Test func undoNeverRemovesATaskTheOwnerCaptured() async throws {
        let owned = try await repository.addTask(NewTask(title: "Explain baseline"))
        await #expect(throws: HerdrTaskError.notFromHerdr) {
            try await repository.undoHerdrAdd(owned.id!)
        }
        #expect(try await repository.tasks().count == 1)
    }

    // MARK: Reading

    @Test func readShowsTheWorkspacesProjectAndTheCurrentNow() async throws {
        try await linkNLPReport()
        let now = try await repository.addTask(NewTask(title: "PhD shortlist", projectName: "Applications",
                                                       nextAction: "Open the spreadsheet"))
        try await repository.moveTask(now.id!, to: .now, .top)
        _ = try await repository.addTask(NewTask(title: "Explain baseline", projectName: "NLP report"))
        _ = try await repository.addFromHerdr(herdrAdd("Re-run ablation"))
        _ = try await repository.addTask(NewTask(title: "Renew library access"))

        let scope = try await repository.herdrScope(for: nlpPane)

        #expect(scope.now?.title == "PhD shortlist")
        #expect(scope.now?.nextAction == "Open the spreadsheet")
        #expect(scope.projectTitle == "NLP report")
        #expect(scope.tasks.map(\.title) == ["Explain baseline", "Re-run ablation"])
        #expect(scope.tasks.map(\.isFromHerdr) == [false, true])
    }

    @Test func outsideHerdrOnlyNowIsRead() async throws {
        try await linkNLPReport()
        let now = try await repository.addTask(NewTask(title: "PhD shortlist", projectName: "Applications"))
        try await repository.moveTask(now.id!, to: .now, .top)
        _ = try await repository.addTask(NewTask(title: "Renew library access"))

        let scope = try await repository.herdrScope(for: nil)

        #expect(scope.now?.title == "PhD shortlist")
        #expect(scope.projectTitle == nil)
        #expect(scope.tasks.isEmpty)
    }

    @Test func aWorkspaceWithoutAProjectReadsOnlyNow() async throws {
        _ = try await repository.addTask(NewTask(title: "Renew library access"))
        let scope = try await repository.herdrScope(for: nlpPane)
        #expect(scope.projectTitle == nil)
        #expect(scope.tasks.isEmpty)
    }
}
