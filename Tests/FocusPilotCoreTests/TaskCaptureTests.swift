import Foundation
import GRDB
import Testing
@testable import FocusPilotCore

@Suite("Task capture storage")
struct TaskCaptureTests {
    private let location: StorageLocation
    private let repository: TaskRepository

    init() throws {
        location = StorageLocation(directory: try makeTemporaryDirectory())
        repository = try TaskRepository(location: location, now: { wednesdayMorningInBogota })
    }

    private func deadline(_ text: String) -> Deadline {
        DeadlineParser(now: wednesdayMorningInBogota, timeZone: bogota).parse(text)!
    }

    @Test func titleAloneIsEnough() async throws {
        _ = try await repository.addTask(NewTask(title: "  Renew library access  "))

        let item = try #require(try await repository.todayTasks().first)
        #expect(item.title == "Renew library access")
        #expect(item.projectTitle == nil)
        #expect(item.nextAction == nil)
        #expect(item.deadline == nil)
    }

    @Test func newTaskStartsAtRevisionOneStampedWithTheClock() async throws {
        let task = try await repository.addTask(NewTask(title: "Write NLP report"))

        let stored = try #require(try await repository.tasks().first)
        #expect(task == stored)
        #expect(stored.revision == 1)
        #expect(stored.createdAt == wednesdayMorningInBogota)
        #expect(stored.updatedAt == wednesdayMorningInBogota)
    }

    @Test func rowsWrittenWithoutBookkeepingGetDatabaseDefaults() async throws {
        let queue = try DatabaseQueue(path: location.ownerDatabaseURL.path)
        try await queue.write { db in
            try db.execute(sql: "INSERT INTO task (title) VALUES ('Raw')")
        }
        try queue.close()

        let stored = try #require(try await repository.tasks().first)
        #expect(stored.revision == 1)
        #expect(abs(stored.createdAt.timeIntervalSinceNow) < 60)
        #expect(stored.updatedAt == stored.createdAt)
    }

    @Test func blankTitleIsRejected() async throws {
        await #expect(throws: NewTask.Invalid.missingTitle) {
            try await repository.addTask(NewTask(title: "   "))
        }
        #expect(try await repository.todayTasks().isEmpty)
    }

    @Test func allCapturedFieldsSurviveReopening() async throws {
        _ = try await repository.addTask(NewTask(
            title: "Write NLP report", projectName: "NLP report",
            deadline: deadline("by Friday 11pm"), nextAction: "Open Overleaf §4.2"))

        let item = try #require(try await TaskRepository(location: location).todayTasks().first)
        #expect(item.projectTitle == "NLP report")
        #expect(item.nextAction == "Open Overleaf §4.2")
        #expect(item.deadline == deadline("by Friday 11pm"))
    }

    @Test func dateOnlyAndTimedDeadlinesAreStoredInDifferentColumns() async throws {
        _ = try await repository.addTask(NewTask(title: "Shortlist", deadline: deadline("by Oct 20")))
        _ = try await repository.addTask(NewTask(title: "Report", deadline: deadline("fri 23:59")))

        let rows = try storedDeadlineColumns()

        #expect(rows[0] == ["2026-10-20", nil, "America/Bogota", "by Oct 20"])
        #expect(rows[1] == [nil, "2026-10-17 04:59:00.000", "America/Bogota", "fri 23:59"])
    }

    @Test func pastDeadlineIsSavedAsEntered() async throws {
        _ = try await repository.addTask(NewTask(title: "Grade claim", deadline: deadline("Oct 13 18:00")))

        let item = try #require(try await repository.todayTasks().first)
        #expect(item.deadline?.isOverdue(at: wednesdayMorningInBogota) == true)
    }

    @Test func projectsAreReusedByNameIgnoringCase() async throws {
        let first = try await repository.addTask(NewTask(title: "A", projectName: "NLP report"))
        let second = try await repository.addTask(NewTask(title: "B", projectName: "nlp REPORT"))

        #expect(first.projectId != nil)
        #expect(first.projectId == second.projectId)
        #expect(try await repository.todayTasks().map(\.projectTitle) == ["NLP report", "NLP report"])
    }

    @Test func databaseRejectsADeadlineThatIsBothDateOnlyAndTimed() throws {
        let queue = try DatabaseQueue(path: location.ownerDatabaseURL.path)

        #expect {
            try queue.write { db in
                try db.execute(sql: """
                    INSERT INTO task (title, deadlineLocalDate, deadlineInstant, deadlineTimeZone, deadlineText)
                    VALUES ('Broken', '2026-10-20', '2026-10-20 05:00:00.000', 'America/Bogota', 'Oct 20')
                    """)
            }
        } throws: { error in
            (error as? DatabaseError)?.extendedResultCode == .SQLITE_CONSTRAINT_CHECK
        }
    }

    // Reads the four deadline columns straight from the file, so the test
    // checks what is stored rather than what the repository decodes.
    private func storedDeadlineColumns() throws -> [[String?]] {
        var configuration = Configuration()
        configuration.readonly = true
        let queue = try DatabaseQueue(path: location.ownerDatabaseURL.path, configuration: configuration)
        return try queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT deadlineLocalDate, deadlineInstant, deadlineTimeZone, deadlineText FROM task ORDER BY id
                """).map { row in (0..<4).map { row[$0] as String? } }
        }
    }
}

@Suite("Owner schema migration")
struct OwnerMigrationTests {
    @Test func tasksSavedBeforeCaptureFieldsExistedAreKept() async throws {
        let location = StorageLocation(directory: try makeTemporaryDirectory())
        let oldDatabase = try DatabaseQueue(path: location.ownerDatabaseURL.path)
        try OwnerSchema.migrator.migrate(oldDatabase, upTo: "owner-v1-task")
        try await oldDatabase.write { db in
            try db.execute(sql: "INSERT INTO task (title) VALUES ('Read chapter 3')")
        }
        try oldDatabase.close()

        let tasks = try await TaskRepository(location: location).todayTasks()

        #expect(tasks.map(\.title) == ["Read chapter 3"])
        #expect(tasks.first?.deadline == nil)
    }

    @Test func tasksSavedBeforeV2GetRevisionOneAndTheMigrationTime() async throws {
        let location = StorageLocation(directory: try makeTemporaryDirectory())
        let oldDatabase = try DatabaseQueue(path: location.ownerDatabaseURL.path)
        try OwnerSchema.migrator.migrate(oldDatabase, upTo: "owner-v1-task")
        try await oldDatabase.write { db in
            try db.execute(sql: "INSERT INTO task (title) VALUES ('Read chapter 3')")
        }
        try oldDatabase.close()

        let task = try #require(try await TaskRepository(location: location).tasks().first)

        #expect(task.revision == 1)
        #expect(abs(task.createdAt.timeIntervalSinceNow) < 60)
        #expect(task.updatedAt == task.createdAt)
    }
}
