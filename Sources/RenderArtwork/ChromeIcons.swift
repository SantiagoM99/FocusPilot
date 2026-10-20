import AppKit
import FocusPilotCore

/// The Chrome extension's icons: the app icon's ring and dot on a rounded
/// system-blue square, drawn at the sizes Chrome asks for. Generated at
/// build time, so no images are committed.
enum ChromeIcons {
    static let sizes = [16, 32, 48, 128]

    @MainActor
    static func write(to directory: URL) throws {
        for size in sizes {
            try writePNG(to: directory.appending(path: "\(size).png"), pixelsWide: size, pixelsHigh: size,
                         appearance: Appearance.light.nsAppearance) { draw(size: CGFloat(size)) }
        }
    }

    private static func draw(size: CGFloat) {
        let scale = size / 1024
        NSColor(srgbRed: 0, green: 0.47843, blue: 1, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size), xRadius: 225 * scale, yRadius: 225 * scale).fill()
        NSColor.white.set()
        let ringRadius = 256 * scale
        let ring = NSBezierPath(ovalIn: NSRect(x: size / 2 - ringRadius, y: size / 2 - ringRadius, width: 2 * ringRadius, height: 2 * ringRadius))
        ring.lineWidth = max(1.5, 76 * scale)
        ring.stroke()
        let dotRadius = max(1.5, 77 * scale)
        NSBezierPath(ovalIn: NSRect(x: size / 2 - dotRadius, y: size / 2 - dotRadius, width: 2 * dotRadius, height: 2 * dotRadius)).fill()
    }
}
