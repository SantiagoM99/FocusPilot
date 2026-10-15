import CoreGraphics
import Testing
@testable import FocusPilotCore

/// Checks the drawn shapes, not the constants: each glyph is rendered into an
/// alpha-only bitmap and sampled at points the logo design fixes (ring radius
/// 6, dot radius 2, in an 18-pt square).
@Suite("Menu bar glyph drawing")
struct MenuBarGlyphDrawingTests {
    private let center = CGPoint(x: 9, y: 9)

    @Test func idleIsARingWithNothingInside() {
        let glyph = RenderedGlyph(.idle)
        #expect(glyph.isInked(at: point(radius: 6, degrees: 0)))
        #expect(!glyph.isInked(at: center))
    }

    @Test func focusingAddsAFilledDot() {
        let glyph = RenderedGlyph(.focusing)
        #expect(glyph.isInked(at: point(radius: 6, degrees: 90)))
        #expect(glyph.isInked(at: center))
        #expect(!glyph.isInked(at: point(radius: 4, degrees: 0)))
    }

    @Test func pausedHasAHollowDot() {
        let glyph = RenderedGlyph(.paused)
        #expect(glyph.isInked(at: point(radius: 2, degrees: 45)))
        #expect(!glyph.isInked(at: center))
        #expect(glyph.isInked(at: point(radius: 6, degrees: 180)))
    }

    @Test func observingDashesTheRing() {
        let glyph = RenderedGlyph(.observing)
        let samples = stride(from: 0.0, to: 360, by: 3).map { glyph.isInked(at: point(radius: 6, degrees: $0)) }
        #expect(samples.contains(true))
        #expect(samples.contains(false))
        #expect(!glyph.isInked(at: center))
    }

    @Test(arguments: MenuBarGlyph.allCases)
    func everyGlyphStaysInsideItsSquare(_ glyph: MenuBarGlyph) {
        let rendered = RenderedGlyph(glyph)
        #expect(!rendered.isInked(at: CGPoint(x: 1.5, y: 9)))
        #expect(!rendered.isInked(at: CGPoint(x: 16.5, y: 9)))
    }

    private func point(radius: CGFloat, degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
    }
}

/// A glyph drawn at 8 px per point into an alpha-only bitmap.
private struct RenderedGlyph {
    static let scale = 8
    private let alpha: [UInt8]
    private let side = Int(MenuBarGlyph.side) * scale

    init(_ glyph: MenuBarGlyph) {
        var pixels = [UInt8](repeating: 0, count: side * side)
        let side = self.side
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
            )!
            context.scaleBy(x: CGFloat(Self.scale), y: CGFloat(Self.scale))
            glyph.draw(in: context)
        }
        alpha = pixels
    }

    func isInked(at point: CGPoint) -> Bool {
        let x = Int(point.x * CGFloat(Self.scale))
        let y = Int(point.y * CGFloat(Self.scale))
        return alpha[y * side + x] > 128
    }
}
