import Foundation

/// The words FocusPilot shows for a deadline: the capture preview, the
/// relative label in Today, and the exact text shown on inspection.
///
/// Everything is written in the deadline's own time zone with a fixed
/// English format, so the owner sees the same interpretation that is saved.
public struct DeadlineText: Sendable {
    public var deadline: Deadline

    public init(_ deadline: Deadline) {
        self.deadline = deadline
    }

    // MARK: Capture preview

    /// "Fri 16 Oct 2026, 23:00" or "Tue 20 Oct 2026".
    public var exact: String {
        switch deadline.due {
        case .dateOnly(let date): format(date.start(in: deadline.timeZone), "EEE d MMM yyyy")
        case .timed(let instant): format(instant, "EEE d MMM yyyy, HH:mm")
        }
    }

    /// "Timed · America/Bogota (GMT−5)" or "Date only · stays on the local date in America/Bogota".
    public var kind: String {
        switch deadline.due {
        case .dateOnly: "Date only · stays on the local date in \(deadline.timeZone.identifier)"
        case .timed(let instant): "Timed · \(zoneWithOffset(at: instant))"
        }
    }

    /// "from “by Oct 20” · no time given, none assumed".
    public var source: String {
        let quoted = "from “\(deadline.originalText)”"
        switch deadline.due {
        case .dateOnly: return quoted + " · no time given, none assumed"
        case .timed: return quoted
        }
    }

    /// "In the past" when the deadline has already passed at `now`, so a
    /// typo like "wed 9am" typed at 10:00 is noticed before saving.
    public func pastWarning(at now: Date) -> String? {
        deadline.isOverdue(at: now) ? "In the past" : nil
    }

    // MARK: Today list

    /// "Due Fri 23:59", "Due tomorrow", "Overdue · Tue 13 Oct, 18:00", ...
    public func relative(at now: Date) -> String {
        let today = LocalDate(containing: now, in: deadline.timeZone)
        let days = Calendar.gregorian(in: deadline.timeZone)
            .dateComponents([.day], from: today.start(in: deadline.timeZone), to: dayStart).day!

        if deadline.isOverdue(at: now) {
            let when = days == 0 ? "today" + time(" ") : dayAndMonth(today: today) + time(", ")
            return "Overdue · \(when) · \(city)"
        }
        switch days {
        case 0: return "Due today" + time(" ")
        case 1: return "Due tomorrow" + time(" ")
        case 2...6: return "Due " + format(dayStart, "EEE") + time(" ")
        default: return "Due " + dayAndMonth(today: today) + time(", ")
        }
    }

    /// The exact reading behind a relative label, for tooltips and detail.
    public var inspection: String {
        switch deadline.due {
        case .dateOnly: "\(exact) · date only · \(deadline.timeZone.identifier)"
        case .timed(let instant): "\(exact) · \(zoneWithOffset(at: instant))"
        }
    }

    // MARK: Pieces

    /// The time zone's city as people write it: "Bogotá", "New York".
    private var city: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en")
        formatter.timeZone = deadline.timeZone
        formatter.dateFormat = "VVV"
        return formatter.string(from: dayStart)
    }

    private var dayStart: Date { deadline.localDate.start(in: deadline.timeZone) }

    /// "Tue 13 Oct", with the year only when it is not the current one.
    private func dayAndMonth(today: LocalDate) -> String {
        format(dayStart, deadline.localDate.year == today.year ? "EEE d MMM" : "EEE d MMM yyyy")
    }

    /// The time of a timed deadline after `separator`; empty for date-only.
    private func time(_ separator: String) -> String {
        guard case .timed(let instant) = deadline.due else { return "" }
        return separator + format(instant, "HH:mm")
    }

    /// "America/Bogota (GMT−5)", using the offset in force at `instant`.
    private func zoneWithOffset(at instant: Date) -> String {
        let seconds = deadline.timeZone.secondsFromGMT(for: instant)
        guard seconds != 0 else { return "\(deadline.timeZone.identifier) (GMT)" }
        let sign = seconds < 0 ? "−" : "+"
        let minutes = abs(seconds) % 3600 / 60
        let offset = sign + String(abs(seconds) / 3600) + (minutes == 0 ? "" : String(format: ":%02d", minutes))
        return "\(deadline.timeZone.identifier) (GMT\(offset))"
    }

    private func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = .gregorian(in: deadline.timeZone)
        formatter.timeZone = deadline.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
