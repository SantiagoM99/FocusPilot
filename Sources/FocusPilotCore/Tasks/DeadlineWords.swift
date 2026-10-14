import Foundation

/// The date half of a typed deadline: "today", "tomorrow", a weekday, a month
/// and day with optional year, or an ISO date.
enum DateWords {
    /// Matches a date at the start of `tokens` and returns the unused rest.
    static func match(_ tokens: [Substring], resolver: DeadlineParser) -> (LocalDate, ArraySlice<Substring>)? {
        guard let first = tokens.first else { return nil }
        let rest = tokens.dropFirst()

        if first == "today" { return (resolver.today, rest) }
        if first == "tomorrow" { return (resolver.today.adding(days: 1), rest) }
        if let weekday = weekdays[first] { return (resolver.coming(weekday: weekday), rest) }
        if let date = LocalDate(isoString: String(first)) { return (date, rest) }

        // "Oct 20 [2026]" or "20 Oct [2026]"
        guard rest.count >= 1 else { return nil }
        let second = rest[rest.startIndex]
        let (month, day): (Int?, Int?) = months[first] != nil
            ? (months[first], dayNumber(second))
            : (months[second], dayNumber(first))
        guard let month, let day else { return nil }

        let afterDay = rest.dropFirst()
        if let yearToken = afterDay.first, yearToken.count == 4, let year = Int(yearToken) {
            let date = LocalDate(year: year, month: month, day: day)
            return date.isValid ? (date, afterDay.dropFirst()) : nil
        }
        guard let date = resolver.nearest(month: month, day: day) else { return nil }
        return (date, afterDay)
    }

    /// "20" or "20th".
    private static func dayNumber(_ token: Substring) -> Int? {
        let digits = token.prefix(while: \.isNumber)
        let suffix = token.dropFirst(digits.count)
        guard ["", "st", "nd", "rd", "th"].contains(suffix), let day = Int(digits), (1...31).contains(day) else { return nil }
        return day
    }

    private static let weekdays: [Substring: Int] = [
        "sun": 1, "sunday": 1,
        "mon": 2, "monday": 2,
        "tue": 3, "tues": 3, "tuesday": 3,
        "wed": 4, "weds": 4, "wednesday": 4,
        "thu": 5, "thur": 5, "thurs": 5, "thursday": 5,
        "fri": 6, "friday": 6,
        "sat": 7, "saturday": 7,
    ]

    private static let months: [Substring: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3,
        "apr": 4, "april": 4, "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7,
        "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9,
        "oct": 10, "october": 10, "nov": 11, "november": 11, "dec": 12, "december": 12,
    ]
}

/// The time half of a typed deadline: "23:59", "11pm", "9:30 am" or "noon".
struct TimeOfDay: Equatable {
    var hour: Int
    var minute: Int

    /// Matches a time at the start of `tokens` and returns the unused rest.
    static func match(_ tokens: ArraySlice<Substring>) -> (TimeOfDay, ArraySlice<Substring>)? {
        guard let first = tokens.first else { return nil }
        if first == "noon" { return (TimeOfDay(hour: 12, minute: 0), tokens.dropFirst()) }

        // A meridiem either sticks to the number ("11pm") or follows it ("11 pm").
        if let meridiem = ["am", "pm"].first(where: { first.hasSuffix($0) }),
           let time = twelveHour(first.dropLast(2), isPM: meridiem == "pm") {
            return (time, tokens.dropFirst())
        }
        let rest = tokens.dropFirst()
        if let next = rest.first, next == "am" || next == "pm",
           let time = twelveHour(first, isPM: next == "pm") {
            return (time, rest.dropFirst())
        }
        // Without a meridiem only "H:MM" counts; a bare "11" is too ambiguous.
        guard first.contains(":"), let time = clock(first), time.hour < 24 else { return nil }
        return (time, rest)
    }

    private static func twelveHour(_ token: Substring, isPM: Bool) -> TimeOfDay? {
        let time = token.contains(":") ? clock(token) : Int(token).map { TimeOfDay(hour: $0, minute: 0) }
        guard let time, (1...12).contains(time.hour) else { return nil }
        let hour = time.hour % 12 + (isPM ? 12 : 0)
        return TimeOfDay(hour: hour, minute: time.minute)
    }

    /// "23:59" → 23, 59. The hour range is checked by the caller.
    private static func clock(_ token: Substring) -> TimeOfDay? {
        let parts = token.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[1].count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              hour >= 0, (0..<60).contains(minute) else { return nil }
        return TimeOfDay(hour: hour, minute: minute)
    }
}
