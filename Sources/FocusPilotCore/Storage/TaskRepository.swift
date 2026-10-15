import Foundation
import GRDB

/// The only writer of FocusPilot's databases.
///
/// Both connections are private to this actor, so every write in the app goes
/// through one of its methods. Other code asks the repository (usually via
/// `FocusCoordinator`) instead of opening the database itself.
///
/// The actor does not make a method atomic: it is reentrant, and another call
/// can run whenever a method awaits. Atomicity comes from GRDB instead, so
/// each logical change must happen inside a single `write` closure, never
/// split across two writes or a read followed by a write.
public actor TaskRepository {
    private let ownerDatabase: DatabasePool
    private let cacheDatabase: DatabasePool

    /// Opens (creating if needed) both databases in `location` and brings each
    /// up to date with its own migrations.
    ///
    /// Only a failure of the owner database is thrown. A cache that cannot be
    /// opened or migrated is deleted and recreated empty, because losing
    /// derived values is cheap and must never keep the owner from their data.
    public init(location: StorageLocation) throws {
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        ownerDatabase = try DatabasePool(path: location.ownerDatabaseURL.path)
        try OwnerSchema.migrator.migrate(ownerDatabase)
        cacheDatabase = try Self.openCache(at: location)
    }

    private static func openCache(at location: StorageLocation) throws -> DatabasePool {
        do {
            return try openAndMigrateCache(at: location)
        } catch {
            for file in location.cacheDatabaseFiles where FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
            return try openAndMigrateCache(at: location)
        }
    }

    private static func openAndMigrateCache(at location: StorageLocation) throws -> DatabasePool {
        let pool = try DatabasePool(path: location.cacheDatabaseURL.path)
        try CacheSchema.migrator.migrate(pool)
        return pool
    }

    // MARK: Owner data

    public func addTask(title: String) async throws -> TaskRecord {
        try await ownerDatabase.write { db in
            var task = TaskRecord(id: nil, title: title)
            try task.insert(db)
            return task
        }
    }

    public func tasks() async throws -> [TaskRecord] {
        try await ownerDatabase.read { db in
            try TaskRecord.order(Column("id")).fetchAll(db)
        }
    }

    // MARK: Cache

    public func storeCacheEntry(key: String, value: Data) async throws {
        try await cacheDatabase.write { db in
            try CacheEntry(key: key, value: value).save(db)
        }
    }

    public func cacheEntry(forKey key: String) async throws -> Data? {
        try await cacheDatabase.read { db in
            try CacheEntry.fetchOne(db, key: key)?.value
        }
    }

    /// Deletes every row of every cache table. The owner database is a
    /// different file and is not opened by this method.
    ///
    /// Rows are deleted in one transaction rather than erasing the file and
    /// re-running migrations: between an erase and the migration, a concurrent
    /// cache read would find no tables at all.
    public func clearCaches() async throws {
        try await cacheDatabase.write { db in
            let tables = try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'
                """)
            for table in tables {
                try db.execute(sql: "DELETE FROM \(table.quotedDatabaseIdentifier)")
            }
        }
    }
}
