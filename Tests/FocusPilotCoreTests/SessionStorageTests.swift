import Foundation
import GRDB
import Testing
@testable import FocusPilotCore

@Suite("Session storage")
struct SessionStorageTests {
    private let location: StorageLocation
    private let repository: TaskRepository

    init() throws {
        location = StorageLocation(directory: try makeTemporaryDirectory())
        repository = try TaskRepository(location: location)
    }

    private func transition(_ session: FocusSession?, publishes: Int) -> FocusTransition {
        FocusTransition(session: session,
                        effects: (session.map { [.persist($0)] } ?? []) + Array(repeating: .publishPolicy(nil), count: publishes))
    }

    @Test func aRecordedSessionIsTheLatestAfterReopening() async throws {
        let session = FocusSession.sample(phase: .paused(since: FocusSession.sampleStart.addingTimeInterval(60)))

        _ = try await repository.record(transition(session, publishes: 1))

        #expect(try await TaskRepository(location: location).latestSession() == session)
    }

    @Test func recordingTheSameSessionAgainUpdatesIt() async throws {
        var session = FocusSession.sample(phase: .running)
        _ = try await repository.record(transition(session, publishes: 1))
        session.phase = .ended(at: session.plannedEnd, reason: .reachedPlannedEnd)

        _ = try await repository.record(transition(session, publishes: 1))

        #expect(try await repository.latestSession() == session)
    }

    @Test func eachPublishGetsTheNextRevisionEvenAfterReopening() async throws {
        #expect(try await repository.record(transition(nil, publishes: 2)).revisions == [1, 2])

        let reopened = try TaskRepository(location: location)

        #expect(try await reopened.record(transition(FocusSession.sample(phase: .running), publishes: 1)).revisions == [3])
    }

    @Test func aNewerSessionReplacesTheOlderAsLatest() async throws {
        let older = FocusSession.sample(phase: .ended(at: FocusSession.sampleStart.addingTimeInterval(60), reason: .completed))
        var newer = FocusSession.sample(phase: .running)
        newer.startedAt = FocusSession.sampleStart.addingTimeInterval(3600)
        _ = try await repository.record(transition(older, publishes: 0))

        _ = try await repository.record(transition(newer, publishes: 0))

        #expect(try await repository.latestSession() == newer)
    }

    // Review of PR #37: a clock set back must not hide the newest session.
    @Test func theLastStartedSessionIsLatestEvenIfItsClockReadsEarlier() async throws {
        var first = FocusSession.sample(phase: .ended(at: FocusSession.sampleStart.addingTimeInterval(60), reason: .completed))
        first.startedAt = FocusSession.sampleStart.addingTimeInterval(3600)
        var second = FocusSession.sample(phase: .running)
        second.id = UUID()
        _ = try await repository.record(transition(first, publishes: 0))
        _ = try await repository.record(transition(second, publishes: 0))

        _ = try await repository.record(transition(first, publishes: 0))

        #expect(try await repository.latestSession() == second)
    }

    @Test func noSessionBeforeTheFirstOne() async throws {
        #expect(try await repository.latestSession() == nil)
    }

    @Test func sessionsLiveInTheOwnerDatabase() throws {
        let owner = try DatabaseInspection(fileAt: location.ownerDatabaseURL)

        #expect(owner.tables.isSuperset(of: ["focusSession", "policyPublication"]))
    }
}

@Suite("Owner schema migration to v12")
struct OwnerMigrationV12Tests {
    // #56: the session table is rebuilt so Now can be empty; saved sessions
    // and the wrap-ups that point at them stay.
    @Test func savedSessionsKeepTheirTaskCoverAllProjectsAndKeepTheirWrapUps() async throws {
        let location = StorageLocation(directory: try makeTemporaryDirectory())
        let oldDatabase = try DatabaseQueue(path: location.ownerDatabaseURL.path)
        try OwnerSchema.migrator.migrate(oldDatabase, upTo: "owner-v11-observe")
        let id = "0B7A3C2E-5D41-4F6A-9E8B-1C2D3E4F5A6B"
        try await oldDatabase.write { db in
            try db.execute(sql: "INSERT INTO task (id, title) VALUES (7, 'Outline the essay')")
            try db.execute(sql: """
                INSERT INTO focusSession (id, taskID, action, mode, startedAt, plannedEnd, phase)
                VALUES (?, 7, 'Outline the essay', 'strict', '2026-10-14 15:00:00.000', '2026-10-14 15:25:00.000',
                        '{"kind":"ended","at":800001500,"reason":"completed"}')
                """, arguments: [id])
            try db.execute(sql: """
                INSERT INTO wrapUp (taskId, sessionId, savedAt, outcome) VALUES (7, ?, '2026-10-14 15:26:00.000', 'Drafted §2')
                """, arguments: [id])
        }
        try oldDatabase.close()

        let repository = try TaskRepository(location: location)

        let session = try #require(try await repository.latestSession())
        #expect(session.taskID == 7 && session.action == "Outline the essay" && session.mode == .strict)
        #expect(session.scope == .allProjects)
        #expect(try await repository.wrapUpHistory(forTask: 7).map(\.outcome) == ["Drafted §2"])
        #expect(OwnerSchema.migrator.migrations.last == "owner-v12-project-sessions")
    }

    @Test func aSessionWithNothingInNowAndChosenProjectsIsStored() async throws {
        let location = StorageLocation(directory: try makeTemporaryDirectory())
        let repository = try TaskRepository(location: location)
        let session = FocusSession.sample(taskID: nil, action: nil,
                                          scope: SessionScope(projects: [ScopedProject(id: 3, title: "NLP report")]))

        _ = try await repository.record(FocusTransition(session: session, effects: [.persist(session)]))

        #expect(try await TaskRepository(location: location).latestSession() == session)
    }
}
