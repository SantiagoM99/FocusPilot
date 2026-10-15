import CoreGraphics

/// Geometry from the logo design, section 2c, in points of an 18 × 18 square.
extension MenuBarGlyph {
    public static let side: CGFloat = 18

    private static let center = CGPoint(x: 9, y: 9)
    private static let ringRadius: CGFloat = 6
    private static let ringStroke: CGFloat = 1.8
    private static let dotRadius: CGFloat = 2
    private static let hollowDotStroke: CGFloat = 1.2
    private static let observingDashes: [CGFloat] = [3, 2.6]

    /// Draws the glyph in the context's current coordinate space, scaled so
    /// that one unit is one point of the 18-pt square.
    ///
    /// Everything is drawn in opaque black: the image is a template, so only
    /// its alpha counts and the system supplies the color.
    public func draw(in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(gray: 0, alpha: 1)
        context.setStrokeColor(gray: 0, alpha: 1)

        context.setLineWidth(Self.ringStroke)
        if self == .observing {
            context.setLineDash(phase: 0, lengths: Self.observingDashes)
        }
        context.strokeEllipse(in: Self.circle(radius: Self.ringRadius))
        context.setLineDash(phase: 0, lengths: [])

        switch self {
        case .focusing:
            context.fillEllipse(in: Self.circle(radius: Self.dotRadius))
        case .paused:
            context.setLineWidth(Self.hollowDotStroke)
            context.strokeEllipse(in: Self.circle(radius: Self.dotRadius))
        case .idle, .observing:
            break
        }
    }

    private static func circle(radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
    }
}
