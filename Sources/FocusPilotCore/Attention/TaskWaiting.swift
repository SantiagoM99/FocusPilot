import Foundation

/// The owner marked a task as waiting on someone or something (decision
/// 0004), optionally with a time to check on it again. Owner-authored state,
/// never inferred.
public struct TaskWaiting: Equatable, Sendable {
    public var taskID: Int64
    /// What it waits on, such as "Ana's review"; nil when the owner gave nothing.
    public var on: String?
    public var since: Date
    /// When the owner wants to check on it; the attention queue holds it from then.
    public var checkAt: Date?

    public init(taskID: Int64, on: String?, since: Date, checkAt: Date?) {
        self.taskID = taskID
        self.on = on
        self.since = since
        self.checkAt = checkAt
    }

    public func checkIsDue(at now: Date) -> Bool {
        checkAt.map { $0 <= now } ?? false
    }
}

/// When to check on a waiting task, as Mark as waiting offers it.
public enum WaitingCheck: CaseIterable, Hashable, Sendable {
    case none, inThirtyMinutes, inOneHour, inThreeHours, tomorrowMorning

    public var title: String {
        switch self {
        case .none: "No time set"
        case .inThirtyMinutes: "In 30 minutes"
        case .inOneHour: "In 1 hour"
        case .inThreeHours: "In 3 hours"
        case .tomorrowMorning: "Tomorrow at 9:00"
        }
    }

    public func date(after now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .none: nil
        case .inThirtyMinutes: now.addingTimeInterval(30 * 60)
        case .inOneHour: now.addingTimeInterval(3600)
        case .inThreeHours: now.addingTimeInterval(3 * 3600)
        case .tomorrowMorning:
            calendar.date(byAdding: .day, value: 1, to: now)
                .flatMap { calendar.date(bySettingHour: 9, minute: 0, second: 0, of: $0) }
        }
    }
}
