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
    /// A correction of the parsed deadline or one picked by hand; it
    /// overrides the parsed phrase until the text changes or it is removed.
    private var chosenDeadline: Deadline?

    public var projectName: String?
    public var nextAction: String?

    public init() {}

    /// Re-splits the text and discards the title correction, which belonged
    /// to the old text. A deadline picked or corrected by hand is kept unless
    /// the new text has a readable deadline. `isKnownWord` says
    /// whether a word is in the spelling dictionary, so "match" is not taken
    /// for a misspelled "March".
    public mutating func setText(_ text: String, now: Date, timeZone: TimeZone, isKnownWord: (String) -> Bool) {
        self.text = text
        split = CaptureSplitter(parser: DeadlineParser(now: now, timeZone: timeZone)).split(text, isKnownWord: isKnownWord)
        editedTitle = nil
        // A deadline picked by hand survives typing unless the new text has
        // a readable deadline of its own. Kept apart from the phrase it may
        // have corrected, it now counts as chosen by hand.
        chosenDeadline = split.deadline == nil ? chosenDeadline.map(\.asChosenByHand) : nil
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
        chosenDeadline ?? (deadlineRemoved ? nil : split.deadline)
    }

    /// A deadline phrase was found but could not be read: saving is blocked.
    public var isDeadlineUnreadable: Bool {
        deadlineText != nil && deadline == nil
    }

    /// A quiet note when a word looks like a misspelled date. It never
    /// blocks saving.
    public var unrecognizedDateHint: String? {
        split.unrecognizedWord.map { "Did you mean a date? “\($0)” wasn’t recognized." }
    }

    public mutating func correctDeadline(_ deadline: Deadline) {
        chosenDeadline = deadline
    }

    /// What the picker shows when opened: the current deadline, or if there
    /// is none (or it could not be read) today, date-only, in `timeZone`.
    /// Nothing is committed until the owner picks (`correctDeadline`).
    public func proposedDeadline(now: Date, timeZone: TimeZone) -> Deadline {
        deadline ?? .chosenByHand(LocalDate(containing: now, in: timeZone), timeZone: timeZone)
    }

    /// Treats the whole text as the title, with no deadline.
    public mutating func removeDeadline() {
        deadlineRemoved = true
        chosenDeadline = nil
    }

    /// The task to save, or nil while the title is blank or the deadline
    /// cannot be read.
    public var newTask: NewTask? {
        guard !isDeadlineUnreadable else { return nil }
        let task = NewTask(title: title, projectName: projectName, deadline: deadline, nextAction: nextAction)
        return task.isValid ? task : nil
    }
}
