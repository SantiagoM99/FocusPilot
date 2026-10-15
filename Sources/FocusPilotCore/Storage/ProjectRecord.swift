import GRDB

/// A project as stored in the owner database. `TaskRepository` matches
/// titles ignoring case and accents, so typing "nlp report" or
/// "investigacion" files the task under the existing project.
struct ProjectRecord: Codable, Equatable, Sendable {
    var id: Int64?
    var title: String
}

extension ProjectRecord: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "project"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
