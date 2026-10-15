import Foundation

/// The single capture field split into a title and an optional deadline.
public struct CaptureSplit: Equatable, Sendable {
    public var title: String
    /// The trailing phrase taken as the deadline, as typed; nil if none.
    public var deadlineText: String?
    /// The parsed deadline; nil when there is no phrase or it is unreadable.
    public var deadline: Deadline?
}

/// Splits "Write NLP report by Friday 11pm" into the title "Write NLP
/// report" and the deadline "by Friday 11pm".
///
/// The deadline is the longest trailing phrase the parser fully reads, if
/// it starts with a marker word (by, due, on, at, before, el, para, antes)
/// or, without one, with an unambiguous date word: a full English weekday or
/// month name, today/tomorrow/hoy/mañana/pasado, or an ISO date, optionally
/// preceded by a time ("12pm Friday"). Abbreviations, Spanish names and bare
/// times are too common in titles ("Read The Sun", "Call Jan 3", "Llamar a
/// Domingo", "Read page 3 pm") to count without a marker.
///
/// When nothing is readable but the end looks like an attempt at a deadline
/// ("by Oct 32", "on fryday 10:00", "mañnana 10:00"), that phrase is returned
/// without a deadline so the sheet can warn and block saving. Otherwise the
/// whole text is the title.
public struct CaptureSplitter: Sendable {
    public var parser: DeadlineParser

    public init(parser: DeadlineParser) {
        self.parser = parser
    }

    public func split(_ text: String) -> CaptureSplit {
        let words = text.ranges(of: /\S+/).map { text[$0] }
        // A readable phrase always wins: in "Present fryday by 10:00" the
        // misspelling stays in the title, where the preview shows it.
        return readablePhrase(text, words)
            ?? unreadablePhrase(text, words)
            ?? CaptureSplit(title: Self.title(text[...]), deadlineText: nil, deadline: nil)
    }

    private func readablePhrase(_ text: String, _ words: [Substring]) -> CaptureSplit? {
        // Start at 1: the title keeps at least one word.
        for index in words.indices.dropFirst() {
            let title = Self.title(text[..<words[index].startIndex])
            guard !title.isEmpty, Self.mayStartDeadline(words[index...]) else { continue }
            let phrase = String(text[words[index].startIndex...])
            if let deadline = parser.parse(phrase) {
                return CaptureSplit(title: title, deadlineText: phrase, deadline: deadline)
            }
        }
        return nil
    }

    private static func mayStartDeadline(_ words: ArraySlice<Substring>) -> Bool {
        guard let first = words.first else { return false }
        if DeadlineParser.fillerWords.contains(Substring(DateVocabulary.normalized(first))) { return true }
        if isUnambiguousStart(first) { return true }
        // "Submit 12pm Friday": a time opens the phrase when such a word follows.
        guard let length = DateVocabulary.timeLength(words) else { return false }
        return words.dropFirst(length).first.map(isUnambiguousStart) == true
    }

    private static func isUnambiguousStart(_ word: Substring) -> Bool {
        let word = DateVocabulary.normalized(word)
        return DateVocabulary.unambiguousStarts.contains(word) || LocalDate(isoString: word) != nil
    }

    /// The longest trailing phrase that opens a date, with or without a marker
    /// before it ("by Oct 32", "mañnana 10:00", "by next tuesdy"), and whose
    /// remaining words could all belong to a date. "on May Day" and "on 3rd
    /// draft" fail the last test and stay in the title; in "Watch the match"
    /// or "Meet at lunch" no date or time follows the near-miss word.
    private func unreadablePhrase(_ text: String, _ words: [Substring]) -> CaptureSplit? {
        for index in words.indices.dropFirst() {
            let rest = words[(index + 1)...]
            let startsAttempt: Bool
            if DeadlineParser.fillerWords.contains(Substring(DateVocabulary.normalized(words[index]))) {
                startsAttempt = DateVocabulary.beginsDate(rest)
            } else {
                startsAttempt = DateVocabulary.opensMisspelledDate(words[index...])
            }
            guard startsAttempt, rest.allSatisfy(DateVocabulary.couldBelongToDate) else { continue }
            let title = Self.title(text[..<words[index].startIndex])
            guard !title.isEmpty else { continue }
            return CaptureSplit(title: title, deadlineText: String(text[words[index].startIndex...]), deadline: nil)
        }
        return nil
    }

    /// The title without trailing separators: "Call bank," becomes "Call bank".
    private static func title(_ text: Substring) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;:-–—")))
    }
}
