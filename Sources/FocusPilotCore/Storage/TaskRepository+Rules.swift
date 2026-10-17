import Foundation
import GRDB

/// What a policy is compiled from, read in the same write that hands out
/// its revision, so a revision always matches the rules it carries.
public struct PolicyInputs: Equatable, Sendable {
    public var rules: [BlockRuleSet]
    public var allowed: [AllowedActivity]
}

/// A saved rule or allowed-list edit: the policy revision it was given and
/// the inputs after it.
public struct PolicyChange: Equatable, Sendable {
    public var revision: Int
    public var inputs: PolicyInputs
}

extension TaskRepository {
    public func policyInputs() async throws -> PolicyInputs {
        try await ownerDatabase.read { db in try Self.policyInputs(db) }
    }

    /// Inserts or updates a rule set, bumping its revision on update. Sites
    /// are normalized here, whoever the caller. Unless `allowWeakening`, an
    /// update that weakens the rule throws `weakensStrictSession` and
    /// changes nothing.
    @discardableResult
    public func save(_ rule: BlockRuleSet, allowWeakening: Bool = true) async throws -> PolicyChange {
        let rule = try ActivityLists.normalized(rule)
        return try await policyChange { db in
            try ActivityLists.validate(rule, allowed: try Self.allowed(db))
            var row = try RuleSetRow(rule)
            if let id = rule.id {
                let saved = try RuleSetRow.fetchOne(db, key: id)
                if !allowWeakening, let old = try saved?.rule(), RuleStrength.weakens(old, to: rule) {
                    throw RuleError.weakensStrictSession
                }
                row.revision = (saved?.revision ?? 0) + 1
                try row.update(db)
            } else {
                row.revision = 1
                try row.insert(db)
            }
        }
    }

    /// Deleting always weakens, so unless `allowWeakening` it throws
    /// `weakensStrictSession`.
    @discardableResult
    public func deleteRuleSet(_ id: Int64, allowWeakening: Bool = true) async throws -> PolicyChange {
        guard allowWeakening else { throw RuleError.weakensStrictSession }
        return try await policyChange { db in _ = try RuleSetRow.deleteOne(db, key: id) }
    }

    /// Allows an entry. A blocked or overlapping target is refused outright,
    /// so allowing never weakens blocking.
    @discardableResult
    public func allow(_ entry: AllowedActivity) async throws -> PolicyChange {
        let entry = try ActivityLists.normalized(entry)
        return try await policyChange { db in
            try ActivityLists.validate(entry, allowed: try Self.allowed(db), rules: try Self.rules(db))
            var row = try AllowedRow(entry)
            row.id = nil
            try row.insert(db)
        }
    }

    @discardableResult
    public func removeAllowed(_ id: Int64) async throws -> PolicyChange {
        try await policyChange { db in _ = try AllowedRow.deleteOne(db, key: id) }
    }

    /// A new revision for the current inputs, such as at launch.
    public func republish() async throws -> PolicyChange {
        try await policyChange { _ in }
    }

    /// Runs `edit`, then hands out the next revision and reads the inputs,
    /// all in one write (decision 0003).
    private func policyChange(_ edit: @escaping @Sendable (Database) throws -> Void) async throws -> PolicyChange {
        try await ownerDatabase.write { db in
            try edit(db)
            return PolicyChange(revision: try Self.nextPolicyRevision(db), inputs: try Self.policyInputs(db))
        }
    }

    static func nextPolicyRevision(_ db: Database) throws -> Int {
        try db.execute(sql: """
            INSERT INTO policyPublication (id, revision) VALUES (1, 1)
            ON CONFLICT(id) DO UPDATE SET revision = revision + 1
            """)
        return try Int.fetchOne(db, sql: "SELECT revision FROM policyPublication WHERE id = 1")!
    }

    static func policyInputs(_ db: Database) throws -> PolicyInputs {
        PolicyInputs(rules: try rules(db), allowed: try allowed(db))
    }

    private static func rules(_ db: Database) throws -> [BlockRuleSet] {
        try RuleSetRow.order(Column("id")).fetchAll(db).map { try $0.rule() }
    }

    private static func allowed(_ db: Database) throws -> [AllowedActivity] {
        try AllowedRow.order(Column("id")).fetchAll(db).map { try $0.entry() }
    }
}
