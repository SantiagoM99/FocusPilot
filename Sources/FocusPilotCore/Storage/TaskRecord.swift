import GRDB

/// A task as stored in the owner database.
///
/// Only the title exists so far; the full task model (project, deadline,
/// next action, ...) arrives with task capture.
public struct TaskRecord: Codable, Equatable, Sendable {
    public var id: Int64?
    public var title: String
}

extension TaskRecord: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "task"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
