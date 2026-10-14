import GRDB

/// Migrations for the owner database.
///
/// Registered migrations are never edited or removed once released: the
/// owner's data was written under them. Change the schema by appending a new
/// migration. There is deliberately no `eraseDatabaseOnSchemaChange` here.
enum OwnerSchema {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("owner-v1-task") { db in
            try db.create(table: TaskRecord.databaseTableName) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("title", .text).notNull()
            }
        }
        return migrator
    }
}
