import Foundation

/// When a task is due, exactly as the owner meant it.
///
/// A date-only deadline ("Oct 20") stays a local date and never acquires a
/// time, so it cannot drift to midnight UTC or to the previous day. A timed
/// deadline ("fri 23:59") is an instant. Both keep the time zone they were
/// entered in and the text the owner typed.
public struct Deadline: Hashable, Sendable {
    public enum Due: Hashable, Sendable {
        case dateOnly(LocalDate)
        case timed(Date)
    }

    public var due: Due
    public var timeZone: TimeZone
    public var originalText: String

    public init(due: Due, timeZone: TimeZone, originalText: String) {
        self.due = due
        self.timeZone = timeZone
        self.originalText = originalText
    }

    /// The day the deadline falls on in its own time zone.
    public var localDate: LocalDate {
        switch due {
        case .dateOnly(let date): date
        case .timed(let instant): LocalDate(containing: instant, in: timeZone)
        }
    }

    /// Whether the deadline has passed at `now`. A date-only deadline is
    /// overdue only once its whole day has ended in its time zone.
    public func isOverdue(at now: Date) -> Bool {
        switch due {
        case .dateOnly(let date): date < LocalDate(containing: now, in: timeZone)
        case .timed(let instant): instant < now
        }
    }
}
