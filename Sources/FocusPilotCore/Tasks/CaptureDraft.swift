import Foundation

/// Everything the capture sheet shows and will save.
///
/// The text is split and its deadline parsed once, when the text changes,
/// against the clock and time zone of that moment. Saving uses that stored
/// result, never a fresh parse, so what is saved is exactly what was
/// previewed even if the clock moved on (for example past midnight).
public struct CaptureDraft: Equatable, Sendable {
    public private(set) var text = ""
    public private(set) var split = CaptureSplit(title: "", deadlineText: nil, deadline: nil)
    public private(set) var deadlineRemoved = false
    private var editedTitle: String?
    private var correctedDeadline: Deadline?

    public var projectName: String?
    public var nextAction: String?

    public init() {}

    /// Re-splits the text and discards earlier corrections to the title and
    /// deadline, since they belonged to the old text.
    public mutating func setText(_ text: String, now: Date, timeZone: TimeZone) {
        self.text = text
        split = CaptureSplitter(parser: DeadlineParser(now: now, timeZone: timeZone)).split(text)
        editedTitle = nil
        correctedDeadline = nil
        deadlineRemoved = false
    }

    /// The split title, or the whole text once the deadline is removed;
    /// setting it records the owner's correction.
    public var title: String {
        get { editedTitle ?? (deadlineRemoved ? text.trimmingCharacters(in: .whitespacesAndNewlines) : split.title) }
        set { editedTitle = newValue }
    }

    /// The typed deadline phrase, if any and not removed.
    public var deadlineText: String? {
        deadlineRemoved ? nil : split.deadlineText
    }

    public var deadline: Deadline? {
        deadlineRemoved ? nil : correctedDeadline ?? split.deadline
    }

    /// A deadline phrase was found but could not be read: saving is blocked.
    public var isDeadlineUnreadable: Bool {
        deadlineText != nil && deadline == nil
    }

    public mutating func correctDeadline(_ deadline: Deadline) {
        correctedDeadline = deadline
    }

    /// Treats the whole text as the title, with no deadline.
    public mutating func removeDeadline() {
        deadlineRemoved = true
        correctedDeadline = nil
    }

    /// The task to save, or nil while the title is blank or the deadline
    /// cannot be read.
    public var newTask: NewTask? {
        guard !isDeadlineUnreadable else { return nil }
        let task = NewTask(title: title, projectName: projectName, deadline: deadline, nextAction: nextAction)
        return task.isValid ? task : nil
    }
}
