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
/// The deadline is the longest trailing phrase the parser fully reads, so
/// "by" or a year inside the title stays there ("Read paper by Smith by Oct
/// 20", "Prepare 2026 budget by fri"). If nothing is readable but the end
/// looks like an attempt at a deadline ("by Oct 32", "on fryday 10:00"), that
/// phrase is returned without a deadline so the sheet can warn and block
/// saving. Otherwise the whole text is the title.
public struct CaptureSplitter: Sendable {
    public var parser: DeadlineParser

    public init(parser: DeadlineParser) {
        self.parser = parser
    }

    public func split(_ text: String) -> CaptureSplit {
        let words = text.ranges(of: /\S+/)
        if let readable = longestReadableSuffix(text, words) {
            // "Present on fryday 10:00": "10:00" reads, but the misspelled
            // day before it shows the deadline started earlier.
            let wordBefore = text[words[readable.index - 1]]
            if Self.looksLikeDate(wordBefore), let unreadable = unreadablePhrase(text, words) {
                return unreadable
            }
            return readable.split
        }
        return unreadablePhrase(text, words) ?? CaptureSplit(title: Self.title(text[...]), deadlineText: nil, deadline: nil)
    }

    private func longestReadableSuffix(_ text: String, _ words: [Range<String.Index>]) -> (index: Int, split: CaptureSplit)? {
        // Start at 1: the title keeps at least one word.
        for index in words.indices.dropFirst() {
            let title = Self.title(text[..<words[index].lowerBound])
            guard !title.isEmpty else { continue }
            let phrase = String(text[words[index].lowerBound...])
            if let deadline = parser.parse(phrase) {
                return (index, CaptureSplit(title: title, deadlineText: phrase, deadline: deadline))
            }
        }
        return nil
    }

    /// The phrase from the last by/due/before/on that is followed by
    /// something date-like.
    private func unreadablePhrase(_ text: String, _ words: [Range<String.Index>]) -> CaptureSplit? {
        for index in words.indices.dropFirst().reversed() where Self.markers.contains(text[words[index]].lowercased()) {
            let after = words[(index + 1)...].map { text[$0] }
            guard after.contains(where: Self.looksLikeDate) else { continue }
            return CaptureSplit(title: Self.title(text[..<words[index].lowerBound]),
                                deadlineText: String(text[words[index].lowerBound...]), deadline: nil)
        }
        return nil
    }

    private static let markers: Set<String> = ["by", "due", "before", "on"]

    /// The title without trailing separators: "Call bank," becomes "Call bank".
    private static func title(_ text: Substring) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;:-–—")))
    }

    // MARK: Looking like a date

    private static func looksLikeDate(_ word: Substring) -> Bool {
        let word = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        if dateNames.contains(word) { return true }
        if word.contains(/^\d{1,2}(:\d{2})?(am|pm)$|^\d{1,2}:\d{2}$|^\d{4}-\d|^\d{1,2}(st|nd|rd|th)$/) { return true }
        // A close misspelling of a long name: "fryday", "tuesdy", "tomorow".
        return word.count >= 5 && longDateNames.contains { editDistance(word, $0) <= 2 }
    }

    private static let longDateNames = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "march", "april", "june", "july", "august",
        "september", "october", "november", "december", "today", "tomorrow", "tonight",
    ]

    private static let dateNames = Set(longDateNames + [
        "mon", "tue", "tues", "wed", "thu", "thur", "thurs", "fri", "sat", "sun",
        "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec",
        "noon", "midnight",
    ])

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
