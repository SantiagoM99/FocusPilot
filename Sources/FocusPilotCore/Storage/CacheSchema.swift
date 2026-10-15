import GRDB

/// Migrations for the cache database. Nothing here may be the only copy of
/// something the owner entered; `TaskRepository.clearCaches()` erases it all.
enum CacheSchema {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("cache-v1-entry") { db in
            try db.create(table: CacheEntry.databaseTableName) { table in
                table.primaryKey("key", .text)
                table.column("value", .blob).notNull()
            }
        }
        return migrator
    }
}
