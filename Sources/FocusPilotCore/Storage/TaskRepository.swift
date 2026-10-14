import Foundation
import GRDB

/// The only writer of FocusPilot's databases.
///
/// Both connections are private to this actor, so every write in the app goes
/// through one of its methods and is serialized by the actor. Other code asks
/// the repository (usually via `FocusCoordinator`) instead of opening the
/// database itself.
public actor TaskRepository {
    private let ownerDatabase: DatabasePool
    private let cacheDatabase: DatabasePool

    /// Opens (creating if needed) both databases in `location` and brings each
    /// up to date with its own migrations.
    public init(location: StorageLocation) throws {
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        ownerDatabase = try DatabasePool(path: location.ownerDatabaseURL.path)
        cacheDatabase = try DatabasePool(path: location.cacheDatabaseURL.path)
        try OwnerSchema.migrator.migrate(ownerDatabase)
        try CacheSchema.migrator.migrate(cacheDatabase)
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

    /// Empties the cache database and recreates its schema. The owner
    /// database is a different file and is not opened by this method.
    public func clearCaches() async throws {
        try await cacheDatabase.erase()
        try CacheSchema.migrator.migrate(cacheDatabase)
    }
}
