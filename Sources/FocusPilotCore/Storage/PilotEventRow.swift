import Foundation
import GRDB

struct PilotEventRow: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "pilotEvent"

    var id: Int64?
    var kind: String
    var at: Date
    var duration: Double?
    var target: String?
    var sessionId: String?
    var taskId: Int64?

    init(_ event: PilotEvent) {
        kind = event.kind.rawValue
        at = event.at
        duration = event.duration
        target = event.target
        sessionId = event.sessionID?.uuidString
        taskId = event.taskID
    }

    /// Nil for a kind a later version wrote.
    var event: PilotEvent? {
        PilotEvent.Kind(rawValue: kind).map {
            PilotEvent(kind: $0, at: at, duration: duration, target: target,
                       sessionID: sessionId.flatMap(UUID.init(uuidString:)), taskID: taskId)
        }
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct RawActivityRow: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "rawActivity"

    var id: Int64?
    var kind: String
    var target: String
    var start: Date
    var end: Date

    init(_ span: ActivitySpan) {
        switch span.key {
        case .app(let bundleID): (kind, target) = ("app", bundleID)
        case .site(let domain): (kind, target) = ("site", domain)
        }
        start = span.start
        end = span.end
    }

    var span: ActivitySpan {
        ActivitySpan(key: kind == "site" ? .site(domain: target) : .app(bundleID: target), start: start, end: end)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
