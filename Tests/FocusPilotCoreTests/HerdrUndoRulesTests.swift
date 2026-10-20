import Foundation
import GRDB
import Testing
@testable import FocusPilotCore

@Suite("Undo of tasks added from Herdr")
struct HerdrUndoRulesTests {
    private let location: StorageLocation
    private let repository: TaskRepository

    init() throws {
        location = StorageLocation(directory: try makeTemporaryDirectory())
        repository = try TaskRepository(location: location, now: { wednesdayMorningInBogota })
    }

    /// Nothing completes tasks yet (#11), so the test writes the state itself.
    private func markDone(_ taskID: Int64) throws {
        try DatabaseQueue(path: location.ownerDatabaseURL.path).write { db in
            try db.execute(sql: "UPDATE task SET status = 'done' WHERE id = ?", arguments: [taskID])
        }
    }

    @Test func theNowTaskCannotBeUndone() async throws {
        let added = try await repository.addFromHerdr(herdrAdd("Re-run ablation"))
        try await repository.moveTask(added.taskID, to: .now, .top)

        await #expect(throws: HerdrTaskError.isNow) { try await repository.undoHerdrAdd(added.taskID) }
        #expect(try await repository.tasks().count == 1)
    }

    @Test func aDoneTaskCannotBeUndone() async throws {
        let added = try await repository.addFromHerdr(herdrAdd("Re-run ablation"))
        try markDone(added.taskID)

        await #expect(throws: HerdrTaskError.isDone) { try await repository.undoHerdrAdd(added.taskID) }
    }

    @Test func theTaskOfARunningSessionCannotBeUndone() async throws {
        let fixture = try await SessionFixture()
        let repository = try TaskRepository(location: fixture.location, now: { wednesdayMorningInBogota })
        let added = try await repository.addFromHerdr(herdrAdd("Re-run ablation"))
        try await fixture.coordinator.moveTask(added.taskID, to: .now, .top)
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)

        await #expect(throws: HerdrTaskError.inRunningSession) { try await fixture.coordinator.undoHerdrAdd(added.taskID) }
        #expect(try await repository.tasks().contains { $0.id == added.taskID })
    }

    // MARK: Where Undo is offered

    @Test func undoIsOfferedOnlyForHerdrTasksInNextOrLater() {
        func item(_ status: TaskStatus, fromHerdr: Bool = true) -> TodayItem {
            TodayItem(id: 7, title: "Re-run ablation", status: status, isFromHerdr: fromHerdr)
        }
        #expect(item(.next).offersHerdrUndo(activeSessionTaskID: nil))
        #expect(item(.later).offersHerdrUndo(activeSessionTaskID: nil))
        #expect(!item(.now).offersHerdrUndo(activeSessionTaskID: nil))
        #expect(!item(.done).offersHerdrUndo(activeSessionTaskID: nil))
        #expect(!item(.next, fromHerdr: false).offersHerdrUndo(activeSessionTaskID: nil))
        #expect(!item(.next).offersHerdrUndo(activeSessionTaskID: 7))
    }
}
