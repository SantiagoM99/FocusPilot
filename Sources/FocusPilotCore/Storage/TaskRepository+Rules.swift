import Foundation
import GRDB

/// What a policy is compiled from, read in the same write that hands out
/// its revision, so a revision always matches the rules it carries.
public struct PolicyInputs: Equatable, Sendable {
    public var rules: [BlockRuleSet]
    public var allowed: [AllowedActivity]
    /// Exceptions unexpired at the repository's clock when read; the
    /// coordinator drops any that expired before it publishes.
    public var exceptions: [TimedException] = []
}

/// What storing a requested exception did.
public enum ExceptionGrant: Equatable, Sendable {
    case granted(PolicyChange)
    /// A running exception already covers it; its expiry stands.
    case alreadyCovered(expiresAt: Date)
}

/// A saved rule or allowed-list edit: the policy revision it was given and
/// the inputs after it.
public struct PolicyChange: Equatable, Sendable {
    public var revision: Int
    public var inputs: PolicyInputs
}

extension TaskRepository {
    public func policyInputs() async throws -> PolicyInputs {
        let now = now()
        return try await ownerDatabase.read { db in try Self.policyInputs(db, at: now) }
    }

    /// Stores a granted exception and hands out the policy revision that
    /// carries it, unless one still running already covers its scope: then
    /// nothing changes and that one's expiry stands (one shared deadline,
    /// whichever profile or the app asks). Checked in the same write, so two
    /// profiles asking at once cannot both grant.
    public func grant(_ exception: TimedException) async throws -> ExceptionGrant {
        let now = now()
        return try await ownerDatabase.write { db in
            if let expiry = try Self.coveringExpiry(of: exception.scope, at: exception.grantedAt, db) {
                return .alreadyCovered(expiresAt: expiry)
            }
            var row = try ExceptionRow(exception)
            row.id = nil
            try row.insert(db)
            return .granted(PolicyChange(revision: try Self.nextPolicyRevision(db), inputs: try Self.policyInputs(db, at: now)))
        }
    }

    /// The expiry of a running exception that already covers `scope`, if
    /// any. Throws `notBlocked` for a site or page no rule blocks.
    public func coveringExpiry(of scope: ExceptionScope, at instant: Date) async throws -> Date? {
        try await ownerDatabase.read { db in try Self.coveringExpiry(of: scope, at: instant, db) }
    }

    private static func coveringExpiry(of scope: ExceptionScope, at instant: Date, _ db: Database) throws -> Date? {
        if let host = scope.siteHost {
            let blocked = try rules(db).flatMap(\.targets).contains {
                if case .site(let domain) = $0 { SiteDomain.domain(host, isWithin: domain) } else { false }
            }
            guard blocked else { throw ExceptionError.notBlocked(host) }
        }
        return try exceptions(db, unexpiredAt: instant).filter { $0.scope.covers(scope) }.map(\.expiresAt).max()
    }

    /// Inserts or updates a rule set, bumping its revision on update. Sites
    /// are normalized here, whoever the caller. An update must carry the
    /// stored revision, or it throws `ruleChanged`: it was made from an older
    /// copy and would undo the edits since. Unless `allowWeakening`, an
    /// update that weakens the rule throws `weakensStrictSession`. Either
    /// way nothing changes.
    @discardableResult
    public func save(_ rule: BlockRuleSet, allowWeakening: Bool = true) async throws -> PolicyChange {
        let rule = try ActivityLists.normalized(rule)
        return try await policyChange { db in
            try ActivityLists.validate(rule, allowed: try Self.allowed(db))
            var row = try RuleSetRow(rule)
            if let id = rule.id {
                guard let saved = try RuleSetRow.fetchOne(db, key: id), saved.revision == rule.revision else {
                    throw RuleError.ruleChanged
                }
                if !allowWeakening, RuleStrength.weakens(try saved.rule(), to: rule) {
                    throw RuleError.weakensStrictSession
                }
                row.revision = saved.revision + 1
                try row.update(db)
            } else {
                row.revision = 1
                try row.insert(db)
            }
        }
    }

    /// Deleting always weakens, so unless `allowWeakening` it throws
    /// `weakensStrictSession`. With a `revision`, it throws `ruleChanged`
    /// unless the stored rule still has it.
    @discardableResult
    public func deleteRuleSet(_ id: Int64, revision: Int? = nil, allowWeakening: Bool = true) async throws -> PolicyChange {
        guard allowWeakening else { throw RuleError.weakensStrictSession }
        return try await policyChange { db in
            if let revision, try RuleSetRow.fetchOne(db, key: id)?.revision != revision {
                throw RuleError.ruleChanged
            }
            _ = try RuleSetRow.deleteOne(db, key: id)
        }
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
        let now = now()
        return try await ownerDatabase.write { db in
            try edit(db)
            return PolicyChange(revision: try Self.nextPolicyRevision(db), inputs: try Self.policyInputs(db, at: now))
        }
    }

    static func nextPolicyRevision(_ db: Database) throws -> Int {
        try db.execute(sql: """
            INSERT INTO policyPublication (id, revision) VALUES (1, 1)
            ON CONFLICT(id) DO UPDATE SET revision = revision + 1
            """)
        return try Int.fetchOne(db, sql: "SELECT revision FROM policyPublication WHERE id = 1")!
    }

    static func policyInputs(_ db: Database, at now: Date) throws -> PolicyInputs {
        PolicyInputs(rules: try rules(db), allowed: try allowed(db), exceptions: try exceptions(db, unexpiredAt: now))
    }

    private static func exceptions(_ db: Database, unexpiredAt now: Date) throws -> [TimedException] {
        try ExceptionRow.filter(Column("expiresAt") > now && Column("cancelledAt") == nil)
            .order(Column("id")).fetchAll(db).map { try $0.exception() }
    }

    private static func rules(_ db: Database) throws -> [BlockRuleSet] {
        try RuleSetRow.order(Column("id")).fetchAll(db).map { try $0.rule() }
    }

    private static func allowed(_ db: Database) throws -> [AllowedActivity] {
        try AllowedRow.order(Column("id")).fetchAll(db).map { try $0.entry() }
    }
}

extension TaskRepository {
    /// Cancels every exception granted up to `instant` that is still
    /// running, keeping the rows.
    static func cancelExceptions(grantedBy instant: Date, _ db: Database) throws {
        try ExceptionRow.filter(Column("cancelledAt") == nil && Column("expiresAt") > instant && Column("grantedAt") <= instant)
            .updateAll(db, Column("cancelledAt").set(to: instant))
        try forgetEndedExceptions(at: instant, db)
    }

    /// Which page was allowed and why is kept only while an exception runs:
    /// once it has expired or was cancelled, its page address and reason are
    /// blanked. The row stays, with its site or app, times and session.
    public func forgetEndedExceptions() async throws {
        let now = now()
        try await ownerDatabase.write { db in try Self.forgetEndedExceptions(at: now, db) }
    }

    static func forgetEndedExceptions(at instant: Date, _ db: Database) throws {
        let blankPage = try JSONCoding.string(ExceptionScope.page(url: ""))
        for var row in try ExceptionRow.filter(Column("expiresAt") <= instant || Column("cancelledAt") != nil).fetchAll(db) {
            let isPage = if case .page(let url) = try row.exception().scope { !url.isEmpty } else { false }
            guard isPage || row.reason != nil else { continue }
            if isPage { row.scope = blankPage }
            row.reason = nil
            try row.update(db)
        }
    }
}
