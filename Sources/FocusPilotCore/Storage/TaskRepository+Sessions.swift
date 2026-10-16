import Foundation
import GRDB

extension TaskRepository {
    /// Records what an engine transition asks to keep: the session, if it
    /// changed, and a new policy revision for each publish, all in one
    /// write. Returns the revisions in publish order.
    @discardableResult
    public func record(_ transition: FocusTransition) async throws -> [Int] {
        try await ownerDatabase.write { db in
            var revisions: [Int] = []
            for effect in transition.effects {
                switch effect {
                case .persist(let session):
                    try SessionRow(session).save(db)
                case .publishPolicy:
                    try db.execute(sql: """
                        INSERT INTO policyPublication (id, revision) VALUES (1, 1)
                        ON CONFLICT(id) DO UPDATE SET revision = revision + 1
                        """)
                    revisions.append(try Int.fetchOne(db, sql: "SELECT revision FROM policyPublication WHERE id = 1")!)
                case .notify:
                    break
                }
            }
            return revisions
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
