import Foundation

/// Reads a typed deadline such as "fri 23:59", "by Oct 20" or "2026-10-20".
///
/// Deterministic on purpose: "now" and the time zone are passed in, so the
/// same text always yields the same deadline in tests. NSDataDetector was
/// tried first and rejected: it reads relative words against the real clock
/// and process time zone, and it gives "Oct 16" and "Oct 16 at noon" the same
/// result, so date-only and timed deadlines cannot be told apart.
///
/// The whole text must be understood. Anything else (including ambiguous
/// times like "12am") returns nil rather than a guess; `hint(for:)` says
/// what to type instead.
public struct DeadlineParser: Sendable {
    public var now: Date
    public var timeZone: TimeZone

    public init(now: Date, timeZone: TimeZone) {
        self.now = now
        self.timeZone = timeZone
    }

    public func parse(_ text: String) -> Deadline? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = Self.tokens(in: trimmed)
        guard !tokens.isEmpty else { return nil }

        guard let (date, time) = dateThenTime(tokens) ?? timeThenDate(tokens) else { return nil }
        let dateOnly = Deadline(due: .dateOnly(date ?? today), timeZone: timeZone, originalText: trimmed)
        guard let time else { return dateOnly }
        return dateOnly.addingTime(hour: time.hour, minute: time.minute)
    }

    /// What to tell the owner when `parse` returned nil for `text`.
    public static func hint(for text: String) -> String {
        if text.lowercased().contains(/midnight|\b12(:00)?\s*am\b/) {
            return "“12am” and “midnight” are ambiguous. Type 23:59 for the end of a day, or 00:00 with the next day's date."
        }
        return "Could not read this deadline. Try “fri 23:59”, “Oct 20” or “2026-10-20”."
    }

    // MARK: Structure

    private typealias Parsed = (date: LocalDate?, time: TimeOfDay?)

    private func dateThenTime(_ tokens: [Substring]) -> Parsed? {
        let (date, rest) = DateWords.match(tokens, resolver: self) ?? (nil, tokens[...])
        let (time, remaining) = TimeOfDay.match(rest) ?? (nil, rest)
        guard remaining.isEmpty, date != nil || time != nil else { return nil }
        return (date, time)
    }

    private func timeThenDate(_ tokens: [Substring]) -> Parsed? {
        guard let (time, rest) = TimeOfDay.match(tokens[...]),
              let (date, remaining) = DateWords.match(Array(rest), resolver: self),
              remaining.isEmpty else { return nil }
        return (date, time)
    }

    static let fillerWords: Set<Substring> = ["by", "due", "on", "at", "before", "el", "para"]

    private static func tokens(in text: String) -> [Substring] {
        Substring(text.lowercased())
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .filter { !fillerWords.contains($0) }
    }

    // MARK: Resolving days

    var calendar: Calendar { .gregorian(in: timeZone) }

    var today: LocalDate { LocalDate(containing: now, in: timeZone) }

    /// The next day with this weekday (1 = Sunday), counting today.
    func coming(weekday: Int) -> LocalDate {
        let todayWeekday = calendar.component(.weekday, from: now)
        return today.adding(days: (weekday - todayWeekday + 7) % 7)
    }

    /// "next fri": that weekday in the week after this one, weeks starting
    /// on Monday. On Wednesday 14 Oct, "next mon" is 19 Oct and "next fri"
    /// is 23 Oct.
    func inFollowingWeek(weekday: Int) -> LocalDate {
        let daysSinceMonday = (calendar.component(.weekday, from: now) + 5) % 7
        let nextMonday = today.adding(days: 7 - daysSinceMonday)
        return nextMonday.adding(days: (weekday + 5) % 7)
    }

    /// Years a typed deadline may name: last year to ten years ahead.
    var plausibleYears: ClosedRange<Int> { today.year - 1 ... today.year + 10 }

    /// A month and day without a year: the next occurrence, looking back up
    /// to a week so a just-missed deadline ("Oct 13" on 14 Oct) stays in the
    /// past instead of moving a year ahead.
    func nextOccurrence(month: Int, day: Int) -> LocalDate? {
        let earliest = today.adding(days: -7)
        return (today.year - 1 ... today.year + 1)
            .map { LocalDate(year: $0, month: month, day: day) }
            .filter { $0.isValid && $0 >= earliest }
            .min()
    }
}
