import Foundation

/// An agent's visible screen reduced to plain text lines for display.
///
/// The text comes from a terminal and is untrusted: escape sequences and
/// control characters are removed so nothing is interpreted, it is never
/// executed or rendered as markup, and only the last lines are kept.
public struct AgentOutputPreview: Equatable, Sendable {
    static let maximumLines = 40
    static let maximumLineLength = 300

    public private(set) var lines: [String]
    /// Lines with text on the screen that was read, including dropped ones.
    public private(set) var totalLineCount: Int

    public init(_ raw: String) {
        let all = Self.strippingEscapes(raw)
            .components(separatedBy: .newlines)
            .map { line in
                String(line.unicodeScalars.filter { $0.properties.generalCategory != .control || $0 == "\t" }.map(Character.init))
                    .trimmingCharacters(in: .whitespaces)
            }
            .filter(Self.hasText)
        lines = all.suffix(Self.maximumLines).map { String($0.prefix(Self.maximumLineLength)) }
        totalLineCount = all.count
    }

    init(storedText: String, totalLineCount: Int) {
        lines = storedText.isEmpty ? [] : storedText.components(separatedBy: "\n")
        self.totalLineCount = totalLineCount
    }

    var storedText: String { lines.joined(separator: "\n") }

    /// CSI sequences (colors, cursor moves, line clears) and OSC sequences
    /// (window titles, links), which end with BEL or ESC \.
    private static func strippingEscapes(_ text: String) -> String {
        let text: String = text.replacing(/\x{1B}\[[0-9;?]*[ -\/]*[@-~]/, with: "")
            .replacing(/\x{1B}\][^\x{07}\x{1B}]*(\x{07}|\x{1B}\\)/, with: "")
            .replacing(/\x{1B}[@-_]/, with: "")
        return text
    }

    /// Lines made only of spaces and box-drawing characters are the agent's
    /// frame, not its output.
    private static func hasText(_ line: String) -> Bool {
        line.unicodeScalars.contains { !$0.properties.isWhitespace && !(0x2500...0x257F).contains($0.value) }
    }
}
