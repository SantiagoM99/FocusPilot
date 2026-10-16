import Foundation
import GRDB
import Synchronization
import Testing
@testable import FocusPilotCore

@Suite("Task ordering storage")
struct TaskOrderingStorageTests {
    private let location: StorageLocation
    private let clock = SettableClock(wednesdayMorningInBogota)
    private let repository: TaskRepository

    init() throws {
        location = StorageLocation(directory: try makeTemporaryDirectory())
        repository = try TaskRepository(location: location, now: { [clock] in clock.now })
    }

    /// Captures tasks titled "A", "B", ... and returns their ids.
    private func capture(_ titles: String...) async throws -> [Int64] {
        var ids: [Int64] = []
        for title in titles {
            ids.append(try await repository.addTask(NewTask(title: title)).id!)
        }
        return ids
    }

    private func todayTitles() async throws -> [String] {
        try await repository.todayTasks().map { "\($0.status.rawValue):\($0.title)" }
    }

    @Test func capturedTasksJoinTheEndOfNext() async throws {
        _ = try await capture("A", "B", "C")

        #expect(try await todayTitles() == ["next:A", "next:B", "next:C"])
    }

    @Test func todayListsNowThenNextThenLaterInManualOrder() async throws {
        let ids = try await capture("A", "B", "C", "D")
        try await repository.moveTask(ids[0], to: .later, .top)
        try await repository.moveTask(ids[3], to: .next, .top)
        try await repository.moveTask(ids[2], to: .now, .top)

        #expect(try await todayTitles() == ["now:C", "next:D", "next:B", "later:A"])
    }

    @Test func todayLeavesOutDoneTasks() async throws {
        let ids = try await capture("A", "B")
        try await rawWrite("UPDATE task SET status = 'done' WHERE id = \(ids[0])")

        #expect(try await todayTitles() == ["next:B"])
    }

    @Test func orderSurvivesRelaunch() async throws {
        let ids = try await capture("A", "B", "C")
        try await repository.moveTask(ids[2], to: .next, .before(ids[0]))
        try await repository.moveTask(ids[1], to: .now, .top)

        let reopened = try TaskRepository(location: location)

        #expect(try await reopened.todayTasks().map(\.title) == ["B", "C", "A"])
        #expect(try await reopened.todayTasks().first?.status == .now)
    }

    @Test func pinningANewNowReturnsTheOldOneToTheTopOfNext() async throws {
        let ids = try await capture("A", "B", "C")
        try await repository.moveTask(ids[0], to: .now, .top)

        try await repository.moveTask(ids[2], to: .now, .top)

        #expect(try await todayTitles() == ["now:C", "next:A", "next:B"])
    }

    @Test func everyMovedTaskGetsANewRevisionAndUpdateTime() async throws {
        let ids = try await capture("A", "B", "C")
        let later = wednesdayMorningInBogota.addingTimeInterval(60)
        clock.set(later)

        try await repository.moveTask(ids[1], to: .next, .top)

        let tasks = Dictionary(uniqueKeysWithValues: try await repository.tasks().map { ($0.id!, $0) })
        #expect(tasks[ids[0]]?.revision == 2)
        #expect(tasks[ids[1]]?.revision == 2)
        #expect(tasks[ids[0]]?.updatedAt == later)
        #expect(tasks[ids[2]]?.revision == 1)
        #expect(tasks[ids[2]]?.updatedAt == wednesdayMorningInBogota)
    }

    @Test func databaseHoldsAtMostOneNow() async throws {
        let ids = try await capture("A", "B")
        try await repository.moveTask(ids[0], to: .now, .top)

        await #expect(throws: DatabaseError.self) {
            try await rawWrite("UPDATE task SET status = 'now' WHERE id = \(ids[1])")
        }
    }

    @Test func databaseRejectsAnUnknownStatus() async throws {
        let ids = try await capture("A")

        await #expect(throws: DatabaseError.self) {
            try await rawWrite("UPDATE task SET status = 'someday' WHERE id = \(ids[0])")
        }
    }

    @Test func tasksAreIndexedByProject() throws {
        let queue = try DatabaseQueue(path: location.ownerDatabaseURL.path)
        let indexed = try queue.read { db in try db.indexes(on: "task").flatMap(\.columns) }

        #expect(indexed.contains("projectId"))
    }

    private func rawWrite(_ sql: String) async throws {
        let queue = try DatabaseQueue(path: location.ownerDatabaseURL.path)
        defer { try? queue.close() }
        try await queue.write { db in try db.execute(sql: sql) }
    }
}

@Suite("Owner schema migration to v3")
struct OwnerMigrationV3Tests {
    @Test func tasksSavedBeforeOrderingKeepCaptureOrderInNext() async throws {
        let location = StorageLocation(directory: try makeTemporaryDirectory())
        let oldDatabase = try DatabaseQueue(path: location.ownerDatabaseURL.path)
        try OwnerSchema.migrator.migrate(oldDatabase, upTo: "owner-v2-capture")
        try await oldDatabase.write { db in
            try db.execute(sql: "INSERT INTO task (title) VALUES ('First'), ('Second'), ('Third')")
        }
        try oldDatabase.close()

        let repository = try TaskRepository(location: location)
        let tasks = try await repository.todayTasks()

        #expect(tasks.map(\.title) == ["First", "Second", "Third"])
        #expect(tasks.allSatisfy { $0.status == .next })
        #expect(try await repository.tasks().allSatisfy { $0.revision == 1 })
    }
}

/// A clock shared with the repository that the test can move.
final class SettableClock: Sendable {
    private let instant: Mutex<Date>

    init(_ instant: Date) {
        self.instant = Mutex(instant)
    }

    var now: Date { instant.withLock { $0 } }

    func set(_ newValue: Date) {
        instant.withLock { $0 = newValue }
    }
}
