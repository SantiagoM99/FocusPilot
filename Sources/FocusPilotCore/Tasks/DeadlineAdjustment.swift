import Foundation

/// Corrections the owner makes in the capture sheet after reading the
/// preview. Each keeps the original text, and each keeps what the owner sees
/// on the wall clock (day and time) rather than the underlying instant.
extension Deadline {
    /// The stored text of a deadline the owner picked in the sheet rather
    /// than typed.
    static let chosenByHandText = "chosen by hand"

    /// A date-only deadline picked by hand; a time can be added afterwards.
    public static func chosenByHand(_ date: LocalDate, timeZone: TimeZone) -> Deadline {
        Deadline(due: .dateOnly(date), timeZone: timeZone, originalText: chosenByHandText)
    }

    public var isChosenByHand: Bool {
        originalText == Self.chosenByHandText
    }

    /// The same deadline, no longer tied to a typed phrase.
    public var asChosenByHand: Deadline {
        Deadline(due: due, timeZone: timeZone, originalText: Self.chosenByHandText)
    }

    public func addingTime(hour: Int, minute: Int) -> Deadline {
        var components = localDate.components
        components.hour = hour
        components.minute = minute
        let instant = Calendar.gregorian(in: timeZone).date(from: components)!
        return Deadline(due: .timed(instant), timeZone: timeZone, originalText: originalText)
    }

    public func removingTime() -> Deadline {
        Deadline(due: .dateOnly(localDate), timeZone: timeZone, originalText: originalText)
    }

    public func moving(to date: LocalDate) -> Deadline {
        let moved = Deadline(due: .dateOnly(date), timeZone: timeZone, originalText: originalText)
        guard let time = wallClockTime else { return moved }
        return moved.addingTime(hour: time.hour, minute: time.minute)
    }

    public func changingTimeZone(to newZone: TimeZone) -> Deadline {
        let moved = Deadline(due: .dateOnly(localDate), timeZone: newZone, originalText: originalText)
        guard let time = wallClockTime else { return moved }
        return moved.addingTime(hour: time.hour, minute: time.minute)
    }

    /// Hour and minute of a timed deadline in its own zone; nil if date-only.
    public var wallClockTime: (hour: Int, minute: Int)? {
        guard case .timed(let instant) = due else { return nil }
        let parts = Calendar.gregorian(in: timeZone).dateComponents([.hour, .minute], from: instant)
        return (parts.hour!, parts.minute!)
    }
}
