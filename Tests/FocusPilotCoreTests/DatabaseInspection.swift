import Foundation
import GRDB

/// What a database file contains, read through a read-only connection so the
/// tests never become a second writer.
struct DatabaseInspection {
    var tables: Set<String>
    var appliedMigrations: [String]

    init(fileAt url: URL) throws {
        var configuration = Configuration()
        configuration.readonly = true
        let queue = try DatabaseQueue(path: url.path, configuration: configuration)
        (tables, appliedMigrations) = try queue.read { db in
            let tables = try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'
                """)
            let migrations = try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid")
            return (Set(tables), migrations)
        }
    }
}
