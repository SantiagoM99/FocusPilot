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
        migrator.registerMigration("owner-v4-herdr") { db in
            // At most one workspace per project, and one project per workspace.
            try db.create(table: HerdrLinkRecord.databaseTableName) { table in
                table.primaryKey("projectId", .integer)
                    .references(ProjectRecord.databaseTableName, onDelete: .cascade)
                table.column("sessionName", .text).notNull()
                table.column("socketPath", .text).notNull()
                table.column("serverStartedAt", .integer).notNull()
                table.column("workspaceId", .text).notNull()
                table.column("label", .text).notNull()
                table.column("cwd", .text)
                table.uniqueKey(["socketPath", "serverStartedAt", "workspaceId"])
            }
            // Every workspace FocusPilot has already imported, created or
            // passed over, so none becomes a project automatically twice,
            // even after its project is unlinked or deleted.
            try db.create(table: "herdrSeenWorkspace") { table in
                table.column("socketPath", .text).notNull()
                table.column("serverStartedAt", .integer).notNull()
                table.column("workspaceId", .text).notNull()
                table.primaryKey(["socketPath", "serverStartedAt", "workspaceId"])
            }
            // Server instances seen at least once. The workspaces already
            // open the first time an instance is seen are not new.
            try db.create(table: "herdrSeenServer") { table in
                table.column("socketPath", .text).notNull()
                table.column("serverStartedAt", .integer).notNull()
                table.primaryKey(["socketPath", "serverStartedAt"])
            }
        }
        migrator.registerMigration("owner-v5-session") { db in
            // One row per session; the phase is the engine's own JSON, which
            // golden tests keep stable.
            try db.create(table: SessionRow.databaseTableName) { table in
                table.primaryKey("id", .text)
                table.column("taskID", .integer).notNull()
                table.column("action", .text).notNull()
                table.column("mode", .text).notNull().check(sql: "mode IN ('normal', 'strict')")
                table.column("startedAt", .datetime).notNull()
                table.column("plannedEnd", .datetime).notNull()
                table.column("phase", .text).notNull()
            }
            try db.create(index: "focusSession_on_startedAt", on: SessionRow.databaseTableName, columns: ["startedAt"])
            // The last policy revision handed out; a single row.
            try db.create(table: "policyPublication") { table in
                table.primaryKey("id", .integer).check(sql: "id = 1")
                table.column("revision", .integer).notNull()
            }
        }
        migrator.registerMigration("owner-v6-herdr-tasks") { db in
            try db.alter(table: TaskRecord.databaseTableName) { table in
                // 'herdr' for tasks added with the focuspilot CLI; nil for the owner's own.
                table.add(column: "source", .text).check(sql: "source IN ('herdr')")
                table.add(column: "sourcePane", .text)
                // The CLI's request ID, so a retried or re-imported add is stored once.
                table.add(column: "clientId", .text)
            }
            try db.create(index: "task_on_clientId", on: TaskRecord.databaseTableName, columns: ["clientId"], unique: true)
        }
        migrator.registerMigration("owner-v8-wrapup") { db in
            // Every wrap-up is kept (owner decision, 2026-10-17); the task's
            // next action is updated in the same write, and the latest row
            // is its return cue. Existing tasks simply have no rows.
            try db.create(table: WrapUpRecord.databaseTableName) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("taskId", .integer).notNull().references(TaskRecord.databaseTableName, onDelete: .cascade)
                table.column("sessionId", .text).notNull().references(SessionRow.databaseTableName)
                table.column("savedAt", .datetime).notNull()
                table.column("outcome", .text)
                table.column("remainingWork", .text)
                table.column("returnCue", .text)
            }
            try db.create(index: "wrapUp_on_taskId", on: WrapUpRecord.databaseTableName, columns: ["taskId"])
        }
        return migrator
    }

    /// The current UTC time in the text format GRDB uses for `Date` columns.
    private static let currentTime = "(strftime('%Y-%m-%d %H:%M:%f', 'now'))"
}
