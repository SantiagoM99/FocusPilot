import AppKit
import FocusPilotCore
import SwiftUI

extension Color {
    /// A redesign color (#70) that follows light or dark mode and Increased
    /// Contrast as the system sets them. Views use these, never hex values.
    static func palette(_ token: Palette.Token) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua,
                                                    .accessibilityHighContrastDarkAqua])
            let dark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
            let increased = match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua
            let rgb = Palette.color(token, dark: dark, increasedContrast: increased)
            return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        })
    }
}

extension ShapeStyle where Self == Color {
    static func palette(_ token: Palette.Token) -> Color { Color.palette(token) }
}
