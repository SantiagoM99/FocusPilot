import Foundation

/// Word tests `CaptureSplitter` uses to decide whether the end of the capture
/// text is a deadline, an attempt at one, or part of the title.
enum DateVocabulary {
    /// Lowercased, with surrounding punctuation removed ("Friday," → "friday").
    static func normalized(_ word: Substring) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }

    /// Words that may open a deadline without a marker word. "May" is left
    /// out: like the abbreviations, it is an ordinary word too.
    static let unambiguousStarts: Set<String> = Set(fullNames).subtracting(["may"])
        .union(["today", "tomorrow", "hoy", "mañana", "pasado"])

    /// True when the words after a marker open a date: a date-like word, or
    /// "next"/"this"/a day number followed by one.
    static func beginsDate(_ words: ArraySlice<Substring>) -> Bool {
        guard let first = words.first else { return false }
        if isDateLike(first) { return true }
        let word = normalized(first)
        let opensWithModifier = ["next", "this", "pasado"].contains(word) || Int(word) != nil
        return opensWithModifier && words.dropFirst().first.map(isDateLike) == true
    }

    /// Could this word be part of a typed date? Date-like words, numbers,
    /// am/pm and the modifiers and markers that appear inside dates.
    static func couldBelongToDate(_ word: Substring) -> Bool {
        let normalized = normalized(word)
        return isDateLike(word)
            || Int(normalized) != nil
            || ["am", "pm", "next", "this", "pasado"].contains(normalized)
            || DeadlineParser.fillerWords.contains(Substring(normalized))
    }

    /// A date name, a relative day, a time or date pattern, or a misspelling
    /// of a date name.
    static func isDateLike(_ word: Substring) -> Bool {
        let word = normalized(word)
        if names.contains(word) { return true }
        if word.contains(/^\d{1,2}(:\d{2})?(am|pm)$|^\d{1,2}:\d{2}$|^\d{4}-\d|^\d{1,2}(st|nd|rd|th)$/) { return true }
        return isMisspelling(word)
    }

    /// A misspelling of a date name, such as "fryday" or "mañnana"; never an
    /// exact name, and never a plural or possessive ("Sundays", "today's").
    static func isMisspelledName(_ word: Substring) -> Bool {
        isMisspelling(normalized(word))
    }

    private static func isMisspelling(_ word: String) -> Bool {
        guard word.count >= 5, !names.contains(word), !word.contains("'"), !word.contains("’") else { return false }
        if word.hasSuffix("s"), names.contains(String(word.dropLast())) { return false }
        return longNames.contains { editDistance(word, $0) <= 2 }
    }

    private static let fullNames = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "march", "april", "may", "june", "july", "august",
        "september", "october", "november", "december",
    ]

    private static let longNames = fullNames.filter { $0.count >= 5 } + ["today", "tomorrow", "tonight", "mañana", "pasado"]

    private static let names = Set(fullNames + [
        "mon", "tue", "tues", "wed", "thu", "thur", "thurs", "fri", "sat", "sun",
        "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec",
        "today", "tomorrow", "tonight", "hoy", "mañana", "noon", "midnight",
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
