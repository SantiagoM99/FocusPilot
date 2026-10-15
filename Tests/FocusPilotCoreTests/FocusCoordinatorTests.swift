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

    @Test func menuBarAccessibilityLabelNamesTheAppAndTheState() {
        #expect(FocusSnapshot().menuBarAccessibilityLabel == "FocusPilot: No current task")
        #expect(FocusSnapshot(currentTaskTitle: "Write the essay").menuBarAccessibilityLabel == "FocusPilot: Write the essay")
    }

    @Test func menuBarSymbolExistsInSFSymbols() {
        #expect(NSImage(systemSymbolName: FocusSnapshot.menuBarSymbolName, accessibilityDescription: nil) != nil)
    }

    @Test func reportsWhetherAnyTaskExists() async throws {
        let repository = try TaskRepository(location: StorageLocation(directory: makeTemporaryDirectory()))
        let coordinator = FocusCoordinator(repository: repository)
        #expect(try await coordinator.hasTasks() == false)

        _ = try await repository.addTask(title: "Write the essay")

        #expect(try await coordinator.hasTasks() == true)
    }
}
