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
        migrator.registerMigration("owner-v2-capture") { db in
            try db.create(table: ProjectRecord.databaseTableName) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("title", .text).notNull().unique().collate(.nocase)
            }
            try db.alter(table: TaskRecord.databaseTableName) { table in
                table.add(column: "projectId", .integer).references(ProjectRecord.databaseTableName, onDelete: .setNull)
                table.add(column: "nextAction", .text)
                table.add(column: "deadlineLocalDate", .text)
                table.add(column: "deadlineInstant", .datetime)
                table.add(column: "deadlineTimeZone", .text)
                // Either no deadline at all, or text and zone plus exactly one
                // of date-only and instant: a date-only deadline never also
                // carries a time.
                table.add(column: "deadlineText", .text).check(sql: """
                    (deadlineText IS NULL AND deadlineTimeZone IS NULL
                        AND deadlineLocalDate IS NULL AND deadlineInstant IS NULL)
                    OR (deadlineText IS NOT NULL AND deadlineTimeZone IS NOT NULL
                        AND (deadlineLocalDate IS NULL) <> (deadlineInstant IS NULL))
                    """)
            }
        }
        return migrator
    }
}
