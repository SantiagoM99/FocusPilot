import Foundation
import GRDB

/// A timed exception as stored; the scope is JSON.
struct ExceptionRow: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "timedException"

    var id: Int64?
    var scope: String
    var grantedAt: Date
    var expiresAt: Date
    var sessionId: String?
    var reason: String?

    init(_ exception: TimedException) throws {
        id = exception.id
        scope = try JSONCoding.string(exception.scope)
        grantedAt = exception.grantedAt
        expiresAt = exception.expiresAt
        sessionId = exception.sessionID?.uuidString
        reason = exception.reason
    }

    func exception() throws -> TimedException {
        TimedException(id: id, scope: try JSONCoding.value(scope), grantedAt: grantedAt, expiresAt: expiresAt,
                       sessionID: sessionId.flatMap(UUID.init(uuidString:)), reason: reason)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
