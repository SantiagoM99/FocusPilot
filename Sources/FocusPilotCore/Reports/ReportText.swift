import Foundation

/// What a report may contain (#67). Report text is shown as plain text and
/// a proposal's message is sent byte for byte, so anything that could make
/// the shown text differ from what an agent receives is refused, never
/// changed:
/// - control characters other than newline and tab, which a terminal acts on;
/// - every invisible format character (Unicode category Cf: zero-width
///   spaces, the byte-order mark, soft hyphens, text-direction controls and
///   tag characters, which can carry hidden instructions to a model), except
///   the zero-width joiner that emoji sequences need;
/// - line and paragraph separators (U+2028, U+2029);
/// - a leading "-", which Herdr 0.9.0 reads as an option (it has no "--").
/// Sizes are capped in characters and in UTF-8 bytes.
public enum ReportRules {
    public static let maxSummary = 2_000
    public static let maxSummaryBytes = 8_000
    public static let maxMessage = 4_000
    public static let maxMessageBytes = 16_000
    public static let maxName = 100
    public static let maxNameBytes = 400

    /// Why the summary cannot be shown, if it cannot.
    public static func summaryProblem(_ summary: String) -> String? {
        if summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "A report needs a summary." }
        if summary.count > maxSummary { return "The summary is longer than \(maxSummary) characters." }
        if summary.utf8.count > maxSummaryBytes { return "The summary is longer than \(maxSummaryBytes) bytes." }
        if hasHiddenCharacters(summary) {
            return "The summary has control, invisible or text-direction characters, which can’t be shown as typed."
        }
        return nil
    }

    /// Why the message cannot be sent exactly as shown, if it cannot.
    public static func messageProblem(_ message: String) -> String? {
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "The proposed message is empty." }
        if message.count > maxMessage { return "The proposed message is longer than \(maxMessage) characters." }
        if message.utf8.count > maxMessageBytes { return "The proposed message is longer than \(maxMessageBytes) bytes." }
        if message.hasPrefix("-") { return "The proposed message can’t start with “-”: Herdr would read it as an option." }
        if hasHiddenCharacters(message) {
            return "The proposed message has control, invisible or text-direction characters, so it can’t be sent exactly as shown."
        }
        return nil
    }

    /// Names and project titles: one short line.
    public static func nameProblem(_ name: String, what: String) -> String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "The \(what) is empty." }
        if name.count > maxName { return "The \(what) is longer than \(maxName) characters." }
        if name.utf8.count > maxNameBytes { return "The \(what) is longer than \(maxNameBytes) bytes." }
        if name.contains(where: \.isNewline) || hasHiddenCharacters(name) { return "The \(what) must be plain text on one line." }
        return nil
    }

    static func hasHiddenCharacters(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x0A, 0x09, 0x200D: return false
            case 0x2028, 0x2029, 0xE0000...0xE007F: return true
            default:
                let category = scalar.properties.generalCategory
                return category == .control || category == .format
            }
        }
    }
}
