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
            // Rebuilt rather than altered: ALTER TABLE ADD COLUMN cannot give
            // a column a non-constant default such as the current time. v1
            // rows keep their id and title and are stamped with the time of
            // this migration, since their real creation time was never stored.
            try db.create(table: "new_task") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("title", .text).notNull()
                table.column("projectId", .integer).references(ProjectRecord.databaseTableName, onDelete: .setNull)
                table.column("nextAction", .text)
                table.column("deadlineLocalDate", .text)
                table.column("deadlineInstant", .datetime)
                table.column("deadlineTimeZone", .text)
                table.column("deadlineText", .text)
                table.column("revision", .integer).notNull().defaults(to: 1)
                table.column("createdAt", .datetime).notNull().defaults(sql: currentTime)
                table.column("updatedAt", .datetime).notNull().defaults(sql: currentTime)
                // Either no deadline at all, or text and zone plus exactly one
                // of date-only and instant: a date-only deadline never also
                // carries a time.
                table.check(sql: """
                    (deadlineText IS NULL AND deadlineTimeZone IS NULL
                        AND deadlineLocalDate IS NULL AND deadlineInstant IS NULL)
                    OR (deadlineText IS NOT NULL AND deadlineTimeZone IS NOT NULL
                        AND (deadlineLocalDate IS NULL) <> (deadlineInstant IS NULL))
                    """)
            }
            try db.execute(sql: "INSERT INTO new_task (id, title) SELECT id, title FROM task")
            try db.drop(table: TaskRecord.databaseTableName)
            try db.rename(table: "new_task", to: TaskRecord.databaseTableName)
        }
        migrator.registerMigration("owner-v3-order") { db in
            try db.alter(table: TaskRecord.databaseTableName) { table in
                table.add(column: "status", .text).notNull().defaults(to: TaskStatus.next.rawValue)
                    .check(sql: "status IN ('now', 'next', 'later', 'done')")
                table.add(column: "rank", .integer).notNull().defaults(to: 0)
            }
            // Earlier tasks keep their capture order in Next. This is not an
            // owner edit, so revision and updatedAt are left alone.
            try db.execute(sql: "UPDATE task SET rank = id")
            // At most one Now, whatever writes the row.
            try db.create(index: "task_one_now", on: TaskRecord.databaseTableName, columns: ["status"],
                          unique: true, condition: Column("status") == TaskStatus.now.rawValue)
            try db.create(index: "task_on_projectId", on: TaskRecord.databaseTableName, columns: ["projectId"])
        }
        return migrator
    }

    /// The current UTC time in the text format GRDB uses for `Date` columns.
    private static let currentTime = "(strftime('%Y-%m-%d %H:%M:%f', 'now'))"
}
