import Foundation
import GRDB

/// A focus session as stored in the owner database.
struct SessionRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "focusSession"

    var id: String
    var taskID: Int64
    var action: String
    var mode: String
    var startedAt: Date
    var plannedEnd: Date
    var phase: String

    init(_ session: FocusSession) throws {
        id = session.id.uuidString
        taskID = session.taskID
        action = session.action
        mode = session.mode.rawValue
        startedAt = session.startedAt
        plannedEnd = session.plannedEnd
        phase = String(decoding: try JSONEncoder().encode(session.phase), as: UTF8.self)
    }

    func session() throws -> FocusSession {
        guard let uuid = UUID(uuidString: id), let mode = SessionMode(rawValue: mode) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unreadable session row \(id)"))
        }
        return FocusSession(id: uuid, taskID: taskID, action: action, mode: mode, startedAt: startedAt,
                            plannedEnd: plannedEnd, phase: try JSONDecoder().decode(SessionPhase.self, from: Data(phase.utf8)))
    }
}
