import Foundation

/// A calendar day with no time and no time zone of its own, such as
/// "20 October 2026". It is not a `Date`: a `Date` is an instant, and turning a
/// day into an instant would pick a time the owner never gave.
public struct LocalDate: Hashable, Comparable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day that contains `instant` on a wall clock in `timeZone`.
    public init(containing instant: Date, in timeZone: TimeZone) {
        let parts = Calendar.gregorian(in: timeZone).dateComponents([.year, .month, .day], from: instant)
        self.init(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    /// `"2026-10-20"`; the form stored in the database.
    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Only the exact form `YYYY-MM-DD` with ASCII digits.
    public init?(isoString: String) {
        guard let match = isoString.wholeMatch(of: /([0-9]{4})-([0-9]{2})-([0-9]{2})/) else { return nil }
        self.init(year: Int(match.1)!, month: Int(match.2)!, day: Int(match.3)!)
        guard isValid else { return nil }
    }

    /// False for days that do not exist, such as 30 February.
    var isValid: Bool {
        let calendar = Calendar.gregorian(in: .gmt)
        guard let start = calendar.date(from: components) else { return false }
        return LocalDate(containing: start, in: .gmt) == self
    }

    var components: DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    /// Midnight at the start of this day in `timeZone`, for arithmetic only.
    func start(in timeZone: TimeZone) -> Date {
        Calendar.gregorian(in: timeZone).date(from: components)!
    }

    func adding(days: Int) -> LocalDate {
        let shifted = Calendar.gregorian(in: .gmt).date(byAdding: .day, value: days, to: start(in: .gmt))!
        return LocalDate(containing: shifted, in: .gmt)
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

extension Calendar {
    /// Gregorian calendar fixed to `timeZone`, so results never depend on the
    /// Mac's current time zone or calendar settings.
    static func gregorian(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
