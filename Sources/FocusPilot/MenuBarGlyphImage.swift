import AppKit
import FocusPilotCore

/// Turns a `MenuBarGlyph` into the template NSImage the menu bar shows.
enum MenuBarGlyphImage {
    @MainActor private static var cache: [MenuBarGlyph: NSImage] = [:]

    @MainActor
    static func image(for glyph: MenuBarGlyph) -> NSImage {
        if let cached = cache[glyph] { return cached }
        let side = MenuBarGlyph.side
        // Drawn on demand at whatever backing scale the menu bar uses, so the
        // vector geometry stays sharp on every display.
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            glyph.draw(in: context)
            return true
        }
        // Template: the system tints it for light, dark and highlighted menu bars.
        image.isTemplate = true
        cache[glyph] = image
        return image
    }
}
