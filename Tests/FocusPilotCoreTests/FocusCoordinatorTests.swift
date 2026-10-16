import AppKit
import Testing
@testable import FocusPilotCore

@Suite("FocusCoordinator")
struct FocusCoordinatorTests {
    @Test func startsWithNoCurrentTask() async throws {
        let repository = try TaskRepository(location: StorageLocation(directory: makeTemporaryDirectory()))
        let coordinator = FocusCoordinator(repository: repository)

        let snapshot = await coordinator.snapshot()

        #expect(snapshot.currentTaskTitle == nil)
        #expect(snapshot.statusText == "No current task")
    }

    @Test func statusTextShowsTheCurrentTask() {
        let snapshot = FocusSnapshot(currentTaskTitle: "Write the essay")

        #expect(snapshot.statusText == "Write the essay")
    }

    @Test func statusTextShowsTheActionOfAnActiveSession() {
        let session = FocusSession.sample(action: "Outline section 2", phase: .running)
        let snapshot = FocusSnapshot(currentTaskTitle: "Write the essay", session: session)

        #expect(snapshot.statusText == "Outline section 2")
    }

    @Test func fallbackSymbolExistsInSFSymbols() {
        #expect(NSImage(systemSymbolName: FocusSnapshot.fallbackSymbolName, accessibilityDescription: nil) != nil)
    }

    @Test func reportsWhetherAnyTaskExists() async throws {
        let repository = try TaskRepository(location: StorageLocation(directory: makeTemporaryDirectory()))
        let coordinator = FocusCoordinator(repository: repository)
        #expect(try await coordinator.hasTasks() == false)

        _ = try await repository.addTask(title: "Write the essay")

        #expect(try await coordinator.hasTasks() == true)
    }

    @Test func currentTaskIsThePinnedNowTask() async throws {
        let repository = try TaskRepository(location: StorageLocation(directory: makeTemporaryDirectory()))
        let coordinator = FocusCoordinator(repository: repository)
        try await coordinator.capture(NewTask(title: "Write the essay"))
        let id = try #require(try await coordinator.todayTasks().first?.id)

        try await coordinator.moveTask(id, to: .now, .top)

        #expect(await coordinator.snapshot().currentTaskTitle == "Write the essay")
        try await coordinator.moveTask(id, to: .next, .top)
        #expect(await coordinator.snapshot().currentTaskTitle == nil)
    }

    @Test func capturingNeverPinsATask() async throws {
        let repository = try TaskRepository(location: StorageLocation(directory: makeTemporaryDirectory()))
        let coordinator = FocusCoordinator(repository: repository)

        try await coordinator.capture(NewTask(title: "Write the essay"))

        #expect(await coordinator.snapshot().currentTaskTitle == nil)
        #expect(try await coordinator.todayTasks().map(\.status) == [.next])
    }

    @Test func capturedTaskAppearsInToday() async throws {
        let repository = try TaskRepository(location: StorageLocation(directory: makeTemporaryDirectory()))
        let coordinator = FocusCoordinator(repository: repository)

        try await coordinator.capture(NewTask(title: "Submit PhD shortlist"))

        #expect(try await coordinator.todayTasks().map(\.title) == ["Submit PhD shortlist"])
    }
}
