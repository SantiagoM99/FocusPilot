import Foundation
import GRDB
import Testing
@testable import FocusPilotCore

@Suite("Wrap-up storage")
struct WrapUpStorageTests {
    private let location: StorageLocation
    private let clock = SettableClock(wednesdayMorningInBogota)
    private let repository: TaskRepository

    init() throws {
        location = StorageLocation(directory: try makeTemporaryDirectory())
        repository = try TaskRepository(location: location, now: { [clock] in clock.now })
    }

    private let sample = WrapUp(
        outcome: "Baseline paragraph drafted in §4.2.",
        remainingWork: "Ablation sentence still needs agent 2's table.",
        returnCue: "Review agent 2's ablation table, then write one sentence under Table 3."
    )

    @Test func savingAWrapUpStoresItAsTaskStateAndMakesTheCueTheNextAction() async throws {
        let task = try await repository.addTask(NewTask(title: "Explain baseline results", nextAction: "Open Overleaf"))
        clock.set(wednesdayMorningInBogota.addingTimeInterval(50 * 60))

        try await repository.saveWrapUp(sample, forTask: task.id!)

        let item = try #require(try await repository.todayTasks().first)
        #expect(item.wrapUp == TaskWrapUp(sample, at: clock.now))
        #expect(item.nextAction == sample.returnCue)
        let stored = try #require(try await repository.tasks().first)
        #expect(stored.revision == task.revision + 1)
        #expect(stored.updatedAt == clock.now)
    }

    @Test func aTaskWithoutAWrapUpHasNone() async throws {
        _ = try await repository.addTask(NewTask(title: "Explain baseline results"))

        #expect(try await repository.todayTasks().first?.wrapUp == nil)
    }

    @Test func savingForATaskThatNoLongerExistsFails() async throws {
        await #expect(throws: TaskRepository.WrapUpError.taskNotFound) {
            try await repository.saveWrapUp(sample, forTask: 42)
        }
    }
}

@Suite("Owner schema migration to v6")
struct OwnerMigrationV6Tests {
    @Test func tasksSavedBeforeWrapUpsHaveNoneAndKeepTheirRevision() async throws {
        let location = StorageLocation(directory: try makeTemporaryDirectory())
        let oldDatabase = try DatabaseQueue(path: location.ownerDatabaseURL.path)
        try OwnerSchema.migrator.migrate(oldDatabase, upTo: "owner-v6-herdr-tasks")
        try await oldDatabase.write { db in
            try db.execute(sql: "INSERT INTO task (title, nextAction, revision) VALUES ('Explain baseline results', 'Open Overleaf', 3)")
        }
        try oldDatabase.close()

        let repository = try TaskRepository(location: location)

        let item = try #require(try await repository.todayTasks().first)
        #expect(item.wrapUp == nil)
        #expect(item.nextAction == "Open Overleaf")
        #expect(try await repository.tasks().first?.revision == 3)
        #expect(OwnerSchema.migrator.migrations.suffix(2) == ["owner-v6-herdr-tasks", "owner-v8-wrapup"])
    }
}
