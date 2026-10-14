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
/// phrases like "next fri") returns nil rather than a guess.
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
        let day = date ?? today

        guard let time else {
            return Deadline(due: .dateOnly(day), timeZone: timeZone, originalText: trimmed)
        }
        var components = day.components
        components.hour = time.hour
        components.minute = time.minute
        guard let instant = calendar.date(from: components) else { return nil }
        return Deadline(due: .timed(instant), timeZone: timeZone, originalText: trimmed)
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

    private static let fillerWords: Set<Substring> = ["by", "due", "on", "at", "before"]

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

    /// A month and day without a year: the occurrence nearest to today, so
    /// "Jan 5" in October means next January and "Oct 13" means yesterday.
    func nearest(month: Int, day: Int) -> LocalDate? {
        let today = today
        return (today.year - 1 ... today.year + 1)
            .map { LocalDate(year: $0, month: month, day: day) }
            .filter(\.isValid)
            .min { distance(today, $0) < distance(today, $1) }
    }

    private func distance(_ a: LocalDate, _ b: LocalDate) -> Int {
        abs(calendar.dateComponents([.day], from: a.start(in: timeZone), to: b.start(in: timeZone)).day!)
    }
}
