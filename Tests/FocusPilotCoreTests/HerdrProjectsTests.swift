import Foundation
import Testing
@testable import FocusPilotCore

let herdrServer = HerdrServer(sessionName: "default", socketPath: "/Users/owner/.config/herdr/herdr.sock",
                              startedAt: instant("2026-09-19T21:05:55-05:00"))
/// The same socket after a Herdr restart.
let restartedHerdrServer = HerdrServer(sessionName: "default", socketPath: herdrServer.socketPath,
                                       startedAt: instant("2026-10-16T08:00:00-05:00"))

let nlpWorkspace = HerdrWorkspace(id: "w4", label: "NLP report", cwd: "/Users/owner/Projects/NLP/nlp_project",
                                  isLinkedWorktree: false)
let thesisWorkspace = HerdrWorkspace(id: "w5", label: "Thesis", cwd: nil, isLinkedWorktree: false)
let agentWorktree = HerdrWorkspace(id: "wP", label: "nlp_project · fix-seeds",
                                   cwd: "/Users/owner/Projects/NLP/nlp_project/.worktrees/fix-seeds", isLinkedWorktree: true)

@Suite("Projects from Herdr workspaces")
struct HerdrProjectsTests {
    private let location: StorageLocation
    private let repository: TaskRepository

    init() throws {
        location = StorageLocation(directory: try makeTemporaryDirectory())
        repository = try TaskRepository(location: location, now: { wednesdayMorningInBogota })
    }

    private func project(_ title: String) async throws -> ProjectSummary {
        try #require(try await repository.projects().first { $0.title == title })
    }

    private func titles() async throws -> [String] {
        try await repository.projects().map(\.title)
    }

    // MARK: Import

    @Test func importedWorkspaceBecomesALinkedProject() async throws {
        try await repository.importHerdrWorkspaces([nlpWorkspace], on: herdrServer)

        let link = try #require(try await project("NLP report").herdrLink)
        #expect(link == HerdrLink(server: herdrServer, workspaceID: "w4", label: "NLP report",
                                  cwd: "/Users/owner/Projects/NLP/nlp_project"))
    }

    @Test func linkIsStoredInTheOwnerDatabase() async throws {
        try await repository.importHerdrWorkspaces([nlpWorkspace], on: herdrServer)

        let reopened = try TaskRepository(location: location)
        #expect(try await reopened.projects().first?.herdrLink?.workspaceID == "w4")
    }

    @Test func importingALinkedWorkspaceAgainChangesNothing() async throws {
        try await repository.importHerdrWorkspaces([nlpWorkspace], on: herdrServer)
        try await repository.importHerdrWorkspaces([nlpWorkspace, thesisWorkspace], on: herdrServer)

        #expect(try await titles() == ["NLP report", "Thesis"])
    }

    @Test func importLinksAnUnlinkedProjectWithTheSameName() async throws {
        _ = try await repository.addTask(NewTask(title: "Explain baseline", projectName: "nlp REPORT"))
        try await repository.importHerdrWorkspaces([nlpWorkspace], on: herdrServer)

        #expect(try await titles() == ["nlp REPORT"])
        #expect(try await project("nlp REPORT").herdrLink?.workspaceID == "w4")
    }

    @Test func importNumbersTheTitleWhenTheNameBelongsToAnotherLinkedProject() async throws {
        try await repository.importHerdrWorkspaces([nlpWorkspace], on: herdrServer)
        let sameLabel = HerdrWorkspace(id: "w9", label: "NLP report", cwd: nil, isLinkedWorktree: false)
        try await repository.importHerdrWorkspaces([sameLabel], on: herdrServer)

        #expect(try await titles() == ["NLP report", "NLP report 2"])
    }

    // MARK: Automatic creation

    @Test func workspacesOpenWhenFocusPilotFirstSeesTheServerAreNotCreated() async throws {
        let created = try await repository.syncHerdrWorkspaces([nlpWorkspace, thesisWorkspace], on: herdrServer)

        #expect(created.isEmpty)
        #expect(try await titles().isEmpty)
    }

    @Test func aWorkspaceThatAppearsLaterBecomesALinkedProject() async throws {
        try await repository.syncHerdrWorkspaces([nlpWorkspace], on: herdrServer)
        let created = try await repository.syncHerdrWorkspaces([nlpWorkspace, thesisWorkspace], on: herdrServer)

        #expect(created == ["Thesis"])
        #expect(try await project("Thesis").herdrLink?.workspaceID == "w5")
    }

    @Test func eachWorkspaceIsCreatedAtMostOnce() async throws {
        try await repository.syncHerdrWorkspaces([], on: herdrServer)
        try await repository.syncHerdrWorkspaces([thesisWorkspace], on: herdrServer)
        let again = try await repository.syncHerdrWorkspaces([thesisWorkspace], on: herdrServer)

        #expect(again.isEmpty)
        #expect(try await titles() == ["Thesis"])
    }

    @Test func agentWorktreeWorkspacesAreSkipped() async throws {
        try await repository.syncHerdrWorkspaces([], on: herdrServer)
        let created = try await repository.syncHerdrWorkspaces([agentWorktree], on: herdrServer)

        #expect(created.isEmpty)
        #expect(try await titles().isEmpty)
    }

    @Test func anUnlinkedProjectIsNotRecreatedForTheSameWorkspace() async throws {
        try await repository.syncHerdrWorkspaces([], on: herdrServer)
        try await repository.syncHerdrWorkspaces([thesisWorkspace], on: herdrServer)
        try await repository.unlinkProject(try #require(try await project("Thesis").id))

        let created = try await repository.syncHerdrWorkspaces([thesisWorkspace], on: herdrServer)

        #expect(created.isEmpty)
        #expect(try await titles() == ["Thesis"])
        #expect(try await project("Thesis").herdrLink == nil)
    }

    @Test func aWorkspaceSeenBeforeARestartIsNotRecreatedAfterIt() async throws {
        try await repository.importHerdrWorkspaces([nlpWorkspace], on: herdrServer)
        try await repository.syncHerdrWorkspaces([nlpWorkspace], on: herdrServer)
        // After a restart Herdr may hand the same workspace a new ID.
        let renumbered = HerdrWorkspace(id: "w1", label: "NLP report", cwd: nlpWorkspace.cwd, isLinkedWorktree: false)

        let created = try await repository.syncHerdrWorkspaces([renumbered], on: restartedHerdrServer)

        #expect(created.isEmpty)
        #expect(try await titles() == ["NLP report"])
    }

    // MARK: Link and unlink

    @Test func unlinkingKeepsTheProjectAndItsTasks() async throws {
        try await repository.importHerdrWorkspaces([nlpWorkspace], on: herdrServer)
        _ = try await repository.addTask(NewTask(title: "Explain baseline", projectName: "NLP report"))
        let id = try #require(try await project("NLP report").id)

        try await repository.unlinkProject(id)

        #expect(try await project("NLP report").herdrLink == nil)
        #expect(try await repository.projectTasks(id).map(\.title) == ["Explain baseline"])
    }

    @Test func aProjectCanBeLinkedFromItsDetail() async throws {
        _ = try await repository.addTask(NewTask(title: "Draft chapter", projectName: "Thesis"))
        let id = try #require(try await project("Thesis").id)

        try await repository.linkProject(id, to: thesisWorkspace, on: herdrServer)

        #expect(try await project("Thesis").herdrLink?.workspaceID == "w5")
    }

    @Test func relinkingReplacesTheStaleLink() async throws {
        try await repository.importHerdrWorkspaces([nlpWorkspace], on: herdrServer)
        let id = try #require(try await project("NLP report").id)
        let renumbered = HerdrWorkspace(id: "w1", label: "NLP report", cwd: nlpWorkspace.cwd, isLinkedWorktree: false)

        try await repository.linkProject(id, to: renumbered, on: restartedHerdrServer)

        #expect(try await project("NLP report").herdrLink
            == HerdrLink(server: restartedHerdrServer, workspaceID: "w1", label: "NLP report", cwd: nlpWorkspace.cwd))
    }

    @Test func aWorkspaceCannotBeLinkedToTwoProjects() async throws {
        try await repository.importHerdrWorkspaces([nlpWorkspace], on: herdrServer)
        _ = try await repository.addTask(NewTask(title: "Draft chapter", projectName: "Thesis"))
        let thesis = try #require(try await project("Thesis").id)

        await #expect(throws: HerdrLinkError.workspaceAlreadyLinked) {
            try await repository.linkProject(thesis, to: nlpWorkspace, on: herdrServer)
        }
    }

    @Test func projectsWithoutAWorkspaceHaveNoLink() async throws {
        _ = try await repository.addTask(NewTask(title: "Renew library access", projectName: "Admin"))
        #expect(try await project("Admin").herdrLink == nil)
    }

    @Test func importedProjectsWithNoTasksAreListed() async throws {
        try await repository.importHerdrWorkspaces([thesisWorkspace], on: herdrServer)
        #expect(try await project("Thesis").openTaskCount == 0)
    }
}
