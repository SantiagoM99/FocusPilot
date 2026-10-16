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

    static func isMarker(_ word: Substring) -> Bool {
        DeadlineParser.fillerWords.contains(Substring(normalized(word)))
    }

    /// True when the words after a marker open a clear date: an exact date
    /// or time word, or "next"/"this"/"pasado"/a day number followed by one.
    /// Further markers and connectors are skipped ("para el 31 de febrero").
    static func beginsDate(_ words: ArraySlice<Substring>) -> Bool {
        let words = words.filter { !isMarker($0) && !DeadlineParser.connectorWords.contains(Substring(normalized($0))) }
        guard let first = words.first else { return false }
        if isDateOrTime(first) { return true }
        let word = normalized(first)
        let opensWithModifier = ["next", "this", "pasado"].contains(word) || Int(word) != nil
        return opensWithModifier && words.dropFirst().first.map(isDateOrTime) == true
    }

    /// Could this word be part of a typed date? Exact date words, numbers,
    /// am/pm and the modifiers, markers and connectors that appear inside
    /// dates. A misspelling is not: it never makes a phrase block saving.
    static func couldBelongToDate(_ word: Substring) -> Bool {
        let normalized = Substring(normalized(word))
        return isDateOrTime(word)
            || Int(normalized) != nil
            || ["am", "pm", "next", "this", "pasado"].contains(normalized)
            || DeadlineParser.fillerWords.contains(normalized)
            || DeadlineParser.connectorWords.contains(normalized)
    }

    /// Is the word at `index` where a date would go? After a marker or
    /// "next"/"this", or at the end, or before a marker, date or time.
    static func isInDatePosition(_ words: [Substring], _ index: Int) -> Bool {
        if index > 0, isMarker(words[index - 1]) || ["next", "this"].contains(normalized(words[index - 1])) { return true }
        let rest = words[(index + 1)...]
        guard let next = rest.first else { return true }
        return isMarker(next) || isDateOrTime(next) || timeLength(rest) != nil
    }

    /// An exact date name, a relative day, or a time or date pattern.
    static func isDateOrTime(_ word: Substring) -> Bool {
        let word = normalized(word)
        return names.contains(word)
            || word.contains(/^\d{1,2}(:\d{2})?(am|pm)$|^\d{1,2}:\d{2}$|^\d{4}-\d|^\d{1,2}(st|nd|rd|th)$/)
    }

    /// How many words the time at the start of `words` takes: one for "12pm",
    /// "10:00" or "noon", two for "12 pm"; nil when they do not open a time.
    static func timeLength(_ words: ArraySlice<Substring>) -> Int? {
        guard let first = words.first.map(normalized) else { return nil }
        if first == "noon" || first.contains(/^\d{1,2}(:\d{2})?(am|pm)$|^\d{1,2}:\d{2}$/) { return 1 }
        let second = words.dropFirst().first.map(normalized)
        return Int(first) != nil && (second == "am" || second == "pm") ? 2 : nil
    }

    /// A misspelling of a date name, such as "fryday", "mañnana" or "vierns";
    /// never an exact name, and never a plural or possessive ("Sundays",
    /// "today's").
    static func isMisspelledName(_ word: Substring) -> Bool {
        let word = normalized(word)
        guard word.count >= 5, !names.contains(word), !word.contains("'"), !word.contains("’") else { return false }
        if word.hasSuffix("s"), names.contains(String(word.dropLast())) { return false }
        return misspellingTargets.contains { editDistance(word, $0) <= 2 }
    }

    /// English names; Spanish ones need a marker ("Domingo" is also a name).
    private static let fullNames = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "march", "april", "may", "june", "july", "august",
        "september", "october", "november", "december",
    ]

    private static let spanishWeekdays = ["lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo"]

    private static let misspellingTargets = fullNames.filter { $0.count >= 5 } + spanishWeekdays
        + ["today", "tomorrow", "tonight", "mañana", "pasado"]

    private static let names = Set(DateWords.weekdays.keys.map(String.init) + DateWords.months.keys.map(String.init) + [
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
