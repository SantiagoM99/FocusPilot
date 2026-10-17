import Foundation
import GRDB

/// A task as stored in the owner database.
///
/// A deadline is spread over four columns: exactly one of
/// `deadlineLocalDate` (date-only, `"2026-10-20"`) and `deadlineInstant`
/// (timed, UTC) is set, together with its time zone and the original text.
/// A CHECK constraint in `OwnerSchema` enforces that; `deadline` is the typed
/// view of those columns.
///
/// `status` and `rank` place the task in Now, Next or Later in the owner's
/// manual order. `revision` starts at 1 and grows with every change to the
/// task, together with `updatedAt`, so derived values can tell they are
/// stale.
public struct TaskRecord: Codable, Equatable, Sendable {
    public var id: Int64?
    public var title: String
    public var projectId: Int64? = nil
    public var nextAction: String? = nil
    public var status = TaskStatus.next
    public var rank = 0
    public var revision = 1
    public var createdAt: Date
    public var updatedAt: Date
    var deadlineLocalDate: String? = nil
    var deadlineInstant: Date? = nil
    var deadlineTimeZone: String? = nil
    var deadlineText: String? = nil
    var source: String? = nil
    var sourcePane: String? = nil
    var clientId: String? = nil

    var isFromHerdr: Bool { source == Self.herdrSource }
    static let herdrSource = "herdr"


    public var deadline: Deadline? {
        get {
            guard let deadlineText, let zone = deadlineTimeZone.flatMap(TimeZone.init(identifier:)) else { return nil }
            if let date = deadlineLocalDate.flatMap(LocalDate.init(isoString:)) {
                return Deadline(due: .dateOnly(date), timeZone: zone, originalText: deadlineText)
            }
            if let deadlineInstant {
                return Deadline(due: .timed(deadlineInstant), timeZone: zone, originalText: deadlineText)
            }
            return nil
        }
        set {
            deadlineLocalDate = nil
            deadlineInstant = nil
            deadlineTimeZone = newValue?.timeZone.identifier
            deadlineText = newValue?.originalText
            switch newValue?.due {
            case .dateOnly(let date): deadlineLocalDate = date.isoString
            case .timed(let instant): deadlineInstant = instant
            case nil: break
            }
        }
    }
}

extension TaskRecord: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "task"

    static let project = belongsTo(ProjectRecord.self)

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
