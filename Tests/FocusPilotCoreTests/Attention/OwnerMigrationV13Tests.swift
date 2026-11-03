import Foundation
import GRDB
import Testing
@testable import FocusPilotCore

@Suite("Owner schema migration to v13")
struct OwnerMigrationV13Tests {
    // #57: a return cue saved on Switch outside a session has no session, so
    // the wrap-up table is rebuilt; earlier wrap-ups keep their session.
    @Test func earlierWrapUpsKeepTheirSessionAndOrder() async throws {
        let location = StorageLocation(directory: try makeTemporaryDirectory())
        let oldDatabase = try DatabaseQueue(path: location.ownerDatabaseURL.path)
        try OwnerSchema.migrator.migrate(oldDatabase, upTo: "owner-v12-project-sessions")
        let session = "0B7A3C2E-5D41-4F6A-9E8B-1C2D3E4F5A6B"
        try await oldDatabase.write { db in
            try db.execute(sql: "INSERT INTO task (id, title) VALUES (7, 'Outline the essay')")
            try db.execute(sql: """
                INSERT INTO focusSession (id, taskID, action, mode, startedAt, plannedEnd, phase)
                VALUES (?, 7, 'Outline the essay', 'normal', '2026-10-14 15:00:00.000', '2026-10-14 15:25:00.000',
                        '{"kind":"ended","at":800001500,"reason":"completed"}')
                """, arguments: [session])
            for outcome in ["First", "Second"] {
                try db.execute(sql: "INSERT INTO wrapUp (taskId, sessionId, savedAt, outcome) VALUES (7, ?, '2026-10-14 15:26:00.000', ?)",
                               arguments: [session, outcome])
            }
        }
        try oldDatabase.close()

        let repository = try TaskRepository(location: location)

        let history = try await repository.wrapUpHistory(forTask: 7)
        #expect(history.map(\.outcome) == ["Second", "First"])
        #expect(history.allSatisfy { $0.sessionID == UUID(uuidString: session) && !$0.isFromSwitch })
        #expect(try await repository.waitingTasks().isEmpty)
        #expect(OwnerSchema.migrator.migrations.last == "owner-v13-attention")
    }
}
