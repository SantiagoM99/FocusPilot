import AppKit

/// Draws into a bitmap of an exact pixel size and saves it as PNG.
@MainActor
func writePNG(to url: URL, pixelsWide: Int, pixelsHigh: Int, appearance: NSAppearance, draw: () -> Void) throws {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    appearance.performAsCurrentDrawingAppearance(draw)
    NSGraphicsContext.restoreGraphicsState()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}

enum Appearance: String, CaseIterable {
    case light, dark

    var nsAppearance: NSAppearance {
        NSAppearance(named: self == .light ? .aqua : .darkAqua)!
    }
}
