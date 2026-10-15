/// The four menu bar images from the logo design (section 2c).
public enum MenuBarGlyph: CaseIterable, Sendable {
    /// Ring only.
    case idle
    /// Ring and a filled dot.
    case focusing
    /// Ring and a hollow dot.
    case paused
    /// Dashed ring.
    case observing
}
