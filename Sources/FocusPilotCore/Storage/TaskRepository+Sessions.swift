import Foundation
import GRDB

extension TaskRepository {
    /// Records what an engine transition asks to keep: the session, if it
    /// changed, and a new policy revision for each publish, all in one
    /// write, with the rule inputs those policies are compiled from. With
    /// `cancellingExceptionsAt`, exceptions granted up to then are cancelled
    /// in the same write (a strict session starting); `events` are stored
    /// in it too.
    @discardableResult
    public func record(_ transition: FocusTransition, cancellingExceptionsAt cancel: Date? = nil,
                       events: [PilotEvent] = []) async throws -> RecordedTransition {
        let now = now()
        return try await ownerDatabase.write { db in
            if let cancel { try Self.cancelExceptions(grantedBy: cancel, db) }
            for event in events {
                var row = PilotEventRow(event)
                try row.insert(db)
            }
            var revisions: [Int] = []
            for effect in transition.effects {
                switch effect {
                case .persist(let session):
                    try SessionRow(session).save(db)
                case .publishPolicy:
                    revisions.append(try Self.nextPolicyRevision(db))
                case .notify:
                    break
                }
            }
            return RecordedTransition(revisions: revisions, inputs: try Self.policyInputs(db, at: now))
        }
    }

    /// Stores what Now changed in the session (its task, title and scope,
    /// nothing else), with a new task as an event, and hands out the policy
    /// revision that names it.
    func recordNowChange(_ session: FocusSession, touched: Bool, at instant: Date) async throws -> PolicyChange {
        let row = try SessionRow(session)
        return try await policyChange { db in
            try db.execute(sql: "UPDATE focusSession SET taskID = ?, action = ?, scope = ? WHERE id = ?",
                           arguments: [row.taskID, row.action, row.scope, row.id])
            if touched, let taskID = session.taskID {
                var event = PilotEventRow(PilotEvent(kind: .taskTouched, at: instant, sessionID: session.id, taskID: taskID))
                try event.insert(db)
            }
        }
    }

    /// The most recently started session, which may have ended. Ordered by
    /// insertion, not `startedAt`, so a clock set back cannot hide it.
    public func latestSession() async throws -> FocusSession? {
        try await ownerDatabase.read { db in
            try SessionRow.order(Column.rowID.desc).fetchOne(db)?.session()
        }
    }
}

/// The revisions handed out for a transition's publishes, in order, and the
/// rule inputs read in the same write.
public struct RecordedTransition: Sendable {
    public var revisions: [Int]
    public var inputs: PolicyInputs
}
