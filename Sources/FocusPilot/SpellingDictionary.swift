import AppKit

/// Asks the system spelling dictionaries whether a word is a real English or
/// Spanish word, so the capture sheet does not take "match" or "marco" for
/// a misspelled month. Only near-miss date words are looked up.
@MainActor
enum SpellingDictionary {
    static func isKnown(_ word: String) -> Bool {
        let checker = NSSpellChecker.shared
        return ["en", "es"].filter(checker.availableLanguages.contains).contains { language in
            checker.checkSpelling(of: word, startingAt: 0, language: language, wrap: false,
                                  inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
        }
    }
}
