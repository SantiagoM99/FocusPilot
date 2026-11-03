import Foundation

/// What a report may contain (#67). Report text is shown as plain text and
/// a proposal's message is sent byte for byte, so anything that could make
/// the shown text differ from what an agent receives is refused, never
/// changed: control characters (which a terminal would act on), the
/// characters that reorder text on screen, and a leading "-", which Herdr
/// 0.9.0 reads as an option (it has no "--" separator).
public enum ReportRules {
    public static let maxSummary = 2_000
    public static let maxMessage = 4_000
    public static let maxName = 100

    /// Why the summary cannot be shown, if it cannot.
    public static func summaryProblem(_ summary: String) -> String? {
        if summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "A report needs a summary." }
        if summary.count > maxSummary { return "The summary is longer than \(maxSummary) characters." }
        if hasHiddenCharacters(summary) { return "The summary has control or text-direction characters, which can’t be shown as typed." }
        return nil
    }

    /// Why the message cannot be sent exactly as shown, if it cannot.
    public static func messageProblem(_ message: String) -> String? {
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "The proposed message is empty." }
        if message.count > maxMessage { return "The proposed message is longer than \(maxMessage) characters." }
        if message.hasPrefix("-") { return "The proposed message can’t start with “-”: Herdr would read it as an option." }
        if hasHiddenCharacters(message) {
            return "The proposed message has control or text-direction characters, so it can’t be sent exactly as shown."
        }
        return nil
    }

    /// Names and project titles: one short line.
    public static func nameProblem(_ name: String, what: String) -> String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "The \(what) is empty." }
        if name.count > maxName { return "The \(what) is longer than \(maxName) characters." }
        if name.contains(where: \.isNewline) || hasHiddenCharacters(name) { return "The \(what) must be plain text on one line." }
        return nil
    }

    /// Control characters other than newline and tab, and bidirectional controls.
    static func hasHiddenCharacters(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            if scalar == "\n" || scalar == "\t" { return false }
            if scalar.properties.generalCategory == .control { return true }
            return (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value)
                || scalar.value == 0x200E || scalar.value == 0x200F || scalar.value == 0x061C
        }
    }
}
