import Foundation
import GRDB

/// Observe-only mode, pilot events and raw activity (#21).
extension TaskRepository {
    /// Raw activity older than this is deleted (DATA_AND_MEMORY.md).
    public static let rawActivityRetention: TimeInterval = 24 * 3600

    /// Turns observe-only on or off and hands out the policy revision that
    /// carries it. Turning it on again keeps the day it first started.
    @discardableResult
    public func setObserveOnly(_ on: Bool) async throws -> PolicyChange {
        let now = now()
        return try await policyChange { db in
            if on {
                try db.execute(sql: "INSERT INTO observeMode (id, since) VALUES (1, ?) ON CONFLICT(id) DO NOTHING",
                               arguments: [now])
            } else {
                try db.execute(sql: "DELETE FROM observeMode")
            }
        }
    }

    public func record(_ record: ActivityRecord) async throws {
        guard !record.isEmpty else { return }
        try await ownerDatabase.write { db in
            for span in record.spans {
                var row = RawActivityRow(span)
                try row.insert(db)
            }
            for event in record.events {
                var row = PilotEventRow(event)
                try row.insert(db)
            }
        }
    }

    public func events(since: Date) async throws -> [PilotEvent] {
        try await ownerDatabase.read { db in
            try PilotEventRow.filter(Column("at") >= since).order(Column("at"), Column("id")).fetchAll(db).compactMap(\.event)
        }
    }

    public func rawActivity() async throws -> [ActivitySpan] {
        try await ownerDatabase.read { db in
            try RawActivityRow.order(Column("start"), Column("id")).fetchAll(db).map(\.span)
        }
    }

    /// Deletes raw activity that ended more than a day ago. Events stay.
    public func pruneRawActivity() async throws {
        let cutoff = now().addingTimeInterval(-Self.rawActivityRetention)
        try await ownerDatabase.write { db in
            _ = try RawActivityRow.filter(Column("end") < cutoff).deleteAll(db)
        }
    }
}
