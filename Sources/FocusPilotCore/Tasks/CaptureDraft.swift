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
    /// The owner's correction of the deadline phrase in the current text.
    /// It belongs to that text and is discarded when the text changes.
    private var phraseCorrection: Deadline?
    /// The deadline the owner last picked by hand. It survives typing: a
    /// readable phrase in the text hides it, and it applies again once the
    /// phrase is gone, so a phrase readable only halfway through a sentence
    /// ("Call Ana at 10am…") cannot delete it. Only `removeDeadline` clears it.
    private var handPick: Deadline?

    public var projectName: String?
    public var nextAction: String?

    public init() {}

    /// Re-splits the text and discards the title and phrase corrections,
    /// which belonged to the old text. `isKnownWord` says
    /// whether a word is in the spelling dictionary, so "match" is not taken
    /// for a misspelled "March".
    public mutating func setText(_ text: String, now: Date, timeZone: TimeZone, isKnownWord: (String) -> Bool) {
        self.text = text
        split = CaptureSplitter(parser: DeadlineParser(now: now, timeZone: timeZone)).split(text, isKnownWord: isKnownWord)
        editedTitle = nil
        phraseCorrection = nil
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
        phraseCorrection ?? readablePhraseDeadline ?? handPick
    }

    private var readablePhraseDeadline: Deadline? {
        deadlineRemoved ? nil : split.deadline
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

    /// Records a deadline the owner set in the picker. While the text has a
    /// readable phrase this corrects it; either way it is also the hand pick
    /// that applies once no readable phrase remains.
    public mutating func correctDeadline(_ deadline: Deadline) {
        if readablePhraseDeadline != nil {
            phraseCorrection = deadline
        }
        handPick = deadline.asChosenByHand
    }

    /// The picker's Done: commits what it shows only when that differs from
    /// the current deadline, so closing an untouched picker over a typed
    /// deadline does not turn it into a hand pick.
    public mutating func confirmPicker(_ shown: Deadline) {
        guard shown != deadline else { return }
        correctDeadline(shown)
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
        phraseCorrection = nil
        handPick = nil
    }

    /// The task to save, or nil while the title is blank or the deadline
    /// cannot be read.
    public var newTask: NewTask? {
        guard !isDeadlineUnreadable else { return nil }
        let task = NewTask(title: title, projectName: projectName, deadline: deadline, nextAction: nextAction)
        return task.isValid ? task : nil
    }
}
