import GRDB

/// A project as stored in the owner database. Titles are unique ignoring
/// case, so typing "nlp report" files the task under "NLP report".
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
