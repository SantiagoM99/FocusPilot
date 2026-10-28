import Foundation

/// The single capture field split into a title and an optional deadline.
public struct CaptureSplit: Equatable, Sendable {
    public var title: String
    /// The trailing phrase taken as the deadline, as typed; nil if none.
    public var deadlineText: String?
    /// The parsed deadline; nil when there is no phrase or it is unreadable.
    public var deadline: Deadline?
    /// A word that looks like a misspelled date ("fryday"), for a hint that
    /// never blocks saving.
    public var unrecognizedWord: String?
}

/// Splits "Write NLP report by Friday 11pm" into the title "Write NLP
/// report" and the deadline "by Friday 11pm".
///
/// The deadline is the longest trailing phrase the parser fully reads that
/// starts with:
/// - a marker word (by, due, on, at, before, el, para, antes, a las, a la);
/// - an unambiguous date word: a full English weekday or month name,
///   today/tomorrow/hoy/mañana/pasado, or an ISO date;
/// - a time written as one token ("10:00", "3pm"), or any time followed by
///   an unambiguous date word ("12 pm Friday").
/// Abbreviations, Spanish names and "N pm" with a space need a marker: they
/// are too common in titles ("Read The Sun", "Llamar a Domingo", "Read page
/// 3 pm").
///
/// A guessed misspelling never blocks saving, drops a readable deadline or
/// takes words out of the title. When no deadline was read, a near-miss
/// date word ("fryday") is named for a quiet hint, unless it is a real word
/// or name: in `NearMissWords` or known to `isKnownWord`, asked in the case
/// typed and, since a capitalized word may be a name ("Call Martha"), in
/// lowercase and capitalized too. A deadline that is only a time ("5pm",
/// meaning today) keeps the hint for a typo before it ("fryday 5pm").
/// Trailing sentence punctuation ("tomorrow.") is not part of the phrase.
///
/// Saving is blocked only for a clear date attempt after a marker that has
/// impossible values ("by Feb 30", "para el 31 de febrero", "at 25:00"):
/// that phrase is returned without a deadline so the sheet can warn, even
/// when it is the whole text.
public struct CaptureSplitter: Sendable {
    public var parser: DeadlineParser

    public init(parser: DeadlineParser) {
        self.parser = parser
    }

    public func split(_ text: String, isKnownWord: (String) -> Bool) -> CaptureSplit {
        // "Buy milk, tomorrow." reads as "Buy milk, tomorrow"; the full stop
        // goes only when a deadline phrase is split off.
        let body = text.replacing(/[\s.!?…]+$/, with: "")
        let words = DateVocabulary.words(in: body)
        if let start = readablePhrase(body, words) {
            let phrase = String(body[words[start].startIndex...])
            var result = CaptureSplit(title: Self.title(body[..<words[start].startIndex]), deadlineText: phrase,
                                      deadline: parser.parse(phrase))
            // A time alone means today: a typo before it is likely the day meant.
            if DateVocabulary.isTimeOnly(words[start...]) {
                result.unrecognizedWord = Self.typo(in: words, before: start, isKnownWord)
            }
            return result
        }
        guard let start = unreadablePhrase(body, words) else {
            var result = CaptureSplit(title: Self.title(text[...]), deadlineText: nil, deadline: nil)
            result.unrecognizedWord = Self.typo(in: words, before: words.count, isKnownWord)
            return result
        }
        var result = CaptureSplit(title: Self.title(body[..<words[start].startIndex]),
                                  deadlineText: String(body[words[start].startIndex...]), deadline: nil)
        result.unrecognizedWord = Self.typo(in: words, before: start, isKnownWord)
        return result
    }

    /// The first near-miss date word before `end` that sits where a date would go.
    private static func typo(in words: [Substring], before end: Int, _ isKnownWord: (String) -> Bool) -> String? {
        (0..<end)
            .first { isTypo(words[$0], isKnownWord) && DateVocabulary.isInDatePosition(words, $0) }
            .map { words[$0].trimmingCharacters(in: .punctuationCharacters) }
    }

    /// A near-miss date word that is not a real word or a name. A capitalized
    /// word may be a name, so the checker is also asked in lowercase and
    /// capitalized ("Martha", "MARCIA"); the bundled list ignores case.
    /// "Fryday" is in neither.
    private static func isTypo(_ word: Substring, _ isKnownWord: (String) -> Bool) -> Bool {
        let asTyped = word.trimmingCharacters(in: .punctuationCharacters)
        guard DateVocabulary.isMisspelledName(word), !NearMissWords.contains(asTyped) else { return false }
        let lowercased = asTyped.lowercased()
        let forms = [asTyped, lowercased, lowercased.prefix(1).uppercased() + lowercased.dropFirst()]
        // An all-caps word is not asked as typed: checkers may accept any
        // word in capitals as an acronym.
        let isAllCaps = asTyped == asTyped.uppercased()
        return !forms.dropFirst(isAllCaps ? 1 : 0).contains(where: isKnownWord)
    }

    /// Where the readable phrase starts, if any.
    private func readablePhrase(_ text: String, _ words: [Substring]) -> Int? {
        // Start at 1: the title keeps at least one word.
        words.indices.dropFirst().first { index in
            Self.mayStartDeadline(words[index...]) && parser.parse(String(text[words[index].startIndex...])) != nil
        }
    }

    private static func mayStartDeadline(_ words: ArraySlice<Substring>) -> Bool {
        guard let first = words.first else { return false }
        if DateVocabulary.isMarker(first) || isUnambiguousStart(first) { return true }
        guard let length = DateVocabulary.timeLength(words) else { return false }
        // "Meet Ana 10:00", "Submit 12 pm Friday". "Read page 3 pm" stays a
        // title: with a space, the number may belong to the title.
        guard let next = words.dropFirst(length).first else {
            return length == 1 && DateVocabulary.normalized(first) != "noon"
        }
        return isUnambiguousStart(next)
    }

    private static func isUnambiguousStart(_ word: Substring) -> Bool {
        let word = DateVocabulary.normalized(word)
        return DateVocabulary.unambiguousStarts.contains(word) || LocalDate(isoString: word) != nil
    }

    /// Where a blocking phrase starts: a marker followed by a clear date,
    /// made only of exact date words, that the parser cannot read ("by Oct
    /// 32", "at 13pm"). "on May Day" and "on 3rd draft" contain other words
    /// and stay in the title.
    private func unreadablePhrase(_ text: String, _ words: [Substring]) -> Int? {
        // From 0: "by Feb 30" alone is still impossible.
        words.indices.first { index in
            let rest = words[(index + 1)...]
            return DateVocabulary.isMarker(words[index])
                && DateVocabulary.beginsDate(rest)
                && rest.allSatisfy(DateVocabulary.couldBelongToDate)
                && parser.parse(String(text[words[index].startIndex...])) == nil
        }
    }

    /// The title without trailing separators: "Call bank," becomes "Call bank".
    private static func title(_ text: Substring) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;:-–—")))
    }
}
