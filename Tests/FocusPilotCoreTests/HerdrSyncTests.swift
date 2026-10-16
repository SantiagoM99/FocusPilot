import Foundation
import Testing
@testable import FocusPilotCore

/// A Herdr whose answer each test sets.
final class FakeHerdr: HerdrWorkspaceSource, @unchecked Sendable {
    var current: HerdrConnection
    init(_ current: HerdrConnection) { self.current = current }
    func connection() async -> HerdrConnection { current }
}

@Suite("Herdr sync through the coordinator")
struct HerdrSyncTests {
    private let repository: TaskRepository
    private let herdr = FakeHerdr(.connected(herdrServer, [nlpWorkspace]))
    private let coordinator: FocusCoordinator

    init() throws {
        repository = try TaskRepository(location: StorageLocation(directory: makeTemporaryDirectory()))
        coordinator = FocusCoordinator(repository: repository, herdr: herdr)
    }

    @Test func refreshReportsTheConnectionAndCreatesProjectsForNewWorkspaces() async throws {
        _ = await coordinator.refreshHerdr()
        herdr.current = .connected(herdrServer, [nlpWorkspace, thesisWorkspace])

        let connection = await coordinator.refreshHerdr()

        #expect(connection == .connected(herdrServer, [nlpWorkspace, thesisWorkspace]))
        #expect(try await repository.projects().map(\.title) == ["Thesis"])
    }

    @Test func nothingIsCreatedWhileHerdrIsUnreachable() async throws {
        _ = await coordinator.refreshHerdr()
        herdr.current = .disconnected(.notRunning)

        #expect(await coordinator.refreshHerdr() == .disconnected(.notRunning))
        #expect(try await repository.projects().isEmpty)
    }

    @Test func projectsAndTasksStayWhenTheWorkspaceDisappears() async throws {
        try await coordinator.importHerdrWorkspaces([nlpWorkspace], on: herdrServer)
        try await coordinator.capture(NewTask(title: "Explain baseline", projectName: "NLP report"))
        herdr.current = .connected(herdrServer, [])

        _ = await coordinator.refreshHerdr()

        let project = try #require(try await repository.projects().first)
        #expect(project.title == "NLP report")
        #expect(project.openTaskCount == 1)
        #expect(HerdrLinkState(try #require(project.herdrLink), herdr.current) == .notFound)
    }

    @Test func withoutHerdrTheCoordinatorStillWorks() async throws {
        let plain = FocusCoordinator(repository: repository)
        #expect(await plain.refreshHerdr() == .disconnected(.binaryNotFound))
        try await plain.capture(NewTask(title: "Renew library access"))
        #expect(try await plain.todayTasks().count == 1)
    }
}
