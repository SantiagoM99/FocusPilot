import Foundation

/// Writes the app icon as an Icon Composer file (`AppIcon.icon`) from the
/// construction in the logo design, section 2a: a flat system-blue
/// background with a white ring and dot on a 1024-pt canvas.
///
/// The squircle, the glass and the dark/tinted renderings come from the
/// system, so the file holds only the background colors and two shapes.
public enum AppIconArtwork {
    static let canvas = 1024
    static let ringRadius = 256  // Ø 512 at the stroke's center line (50%)
    static let ringStroke = 76  // 7.5%
    static let dotRadius = 77  // Ø 154 (15%)

    /// #007AFF and #0A84FF, the system blue in light and dark appearance.
    static let lightFill = "srgb:0.00000,0.47843,1.00000,1.00000"
    static let darkFill = "srgb:0.03922,0.51765,1.00000,1.00000"

    public static func writeIconComposerFile(to url: URL) throws {
        let assets = url.appending(path: "Assets", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try ringSVG.write(to: assets.appending(path: "ring.svg"), atomically: true, encoding: .utf8)
        try dotSVG.write(to: assets.appending(path: "dot.svg"), atomically: true, encoding: .utf8)
        try iconJSON().write(to: url.appending(path: "icon.json"))
    }

    static var ringSVG: String {
        svg(##"<circle cx="512" cy="512" r="\##(ringRadius)" fill="none" stroke="#FFFFFF" stroke-width="\##(ringStroke)"/>"##)
    }

    static var dotSVG: String {
        svg(##"<circle cx="512" cy="512" r="\##(dotRadius)" fill="#FFFFFF"/>"##)
    }

    private static func svg(_ shape: String) -> String {
        """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(canvas)" height="\(canvas)" viewBox="0 0 \(canvas) \(canvas)">\(shape)</svg>

        """
    }

    private static func iconJSON() throws -> Data {
        let icon: [String: Any] = [
            "fill-specializations": [
                ["value": ["solid": lightFill]],
                ["appearance": "dark", "value": ["solid": darkFill]],
            ],
            "groups": [
                ["layers": [
                    ["name": "dot", "image-name": "dot.svg"],
                    ["name": "ring", "image-name": "ring.svg"],
                ]],
            ],
            "supported-platforms": ["squares": ["macOS"]],
        ]
        return try JSONSerialization.data(withJSONObject: icon, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}
