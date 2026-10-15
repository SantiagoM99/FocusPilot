import AppKit
import FocusPilotCore

/// Menu bar glyphs for the owner's visual review, drawn with the same code
/// the app uses and tinted the way the system tints template images.
///
/// The menu bar background is a flat stand-in: on macOS 26 the real bar is
/// translucent over the wallpaper.
@MainActor
enum GlyphPreviews {
    private static let scale: CGFloat = 4
    private static let barHeight: CGFloat = 24
    private static let states: [(MenuBarGlyph, String, time: String?)] = [
        (.idle, "idle", nil), (.focusing, "focusing", "24:08"), (.paused, "paused", "24:08"), (.observing, "observing", nil),
    ]

    static func write(to directory: URL) throws {
        for appearance in Appearance.allCases {
            for (glyph, name, time) in states {
                try writeStrip(glyph: glyph, time: nil, appearance: appearance,
                               to: directory.appending(path: "menubar-\(name)-\(appearance.rawValue).png"))
                if time != nil {
                    try writeStrip(glyph: glyph, time: time, appearance: appearance,
                                   to: directory.appending(path: "menubar-\(name)-with-time-\(appearance.rawValue).png"))
                }
            }
        }
    }

    private static func writeStrip(glyph: MenuBarGlyph, time: String?, appearance: Appearance, to url: URL) throws {
        let width: CGFloat = time == nil ? 40 : 80
        try writePNG(
            to: url, pixelsWide: Int(width * scale), pixelsHigh: Int(barHeight * scale),
            appearance: appearance.nsAppearance
        ) {
            let context = NSGraphicsContext.current!.cgContext
            context.scaleBy(x: scale, y: scale)
            NSColor(white: appearance == .light ? 0.96 : 0.13, alpha: 1).setFill()
            CGRect(x: 0, y: 0, width: width, height: barHeight).fill()

            // Menu bar ink: labelColor in the current appearance.
            let glyphOrigin = CGPoint(x: 11, y: (barHeight - MenuBarGlyph.side) / 2)
            drawTemplate(glyph, at: glyphOrigin, tint: NSColor.labelColor.cgColor, in: context)

            if let time {
                let color = glyph == .paused ? NSColor.secondaryLabelColor : NSColor.labelColor
                let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
                let text = NSAttributedString(string: time, attributes: [.font: font, .foregroundColor: color])
                text.draw(at: CGPoint(x: glyphOrigin.x + MenuBarGlyph.side + 4, y: (barHeight - text.size().height) / 2))
            }
        }
    }

    /// Template semantics: only the glyph's alpha is kept, filled with `tint`.
    private static func drawTemplate(_ glyph: MenuBarGlyph, at origin: CGPoint, tint: CGColor, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        glyph.draw(in: context)
        context.setBlendMode(.sourceIn)
        context.setFillColor(tint)
        context.fill(CGRect(x: 0, y: 0, width: MenuBarGlyph.side, height: MenuBarGlyph.side))
        context.endTransparencyLayer()
        context.restoreGState()
    }
}
