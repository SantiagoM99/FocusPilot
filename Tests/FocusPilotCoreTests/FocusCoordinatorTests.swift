import Testing
@testable import FocusPilotCore

@Suite("FocusCoordinator")
struct FocusCoordinatorTests {
    @Test func startsWithNoCurrentTask() async throws {
        let repository = try TaskRepository(location: StorageLocation(directory: makeTemporaryDirectory()))
        let coordinator = FocusCoordinator(repository: repository)

        let snapshot = await coordinator.snapshot()

        #expect(snapshot.currentTaskTitle == nil)
        #expect(snapshot.menuBarTitle == "No current task")
    }

    @Test func menuBarTitleShowsTheCurrentTask() {
        let snapshot = FocusSnapshot(currentTaskTitle: "Write the essay")

        #expect(snapshot.menuBarTitle == "Write the essay")
    }
}
