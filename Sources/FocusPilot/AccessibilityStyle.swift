import AppKit
import SwiftUI

/// Increased Contrast and Reduce Transparency, as design 04 shows them:
/// status dots get a label-colored outline, quiet surfaces get a separator
/// border, and bar materials fall back to the opaque window background.
extension View {
    /// A 1 pt outline in the label color around a status dot with Increased Contrast.
    func contrastOutline() -> some View {
        modifier(ContrastOutline())
    }

    /// A separator border around a quiet surface (a tinted card) with Increased Contrast.
    func contrastBorder(cornerRadius: CGFloat) -> some View {
        modifier(ContrastBorder(cornerRadius: cornerRadius))
    }

    /// The bar material, or windowBackgroundColor with no blur under Reduce Transparency.
    func barBackground() -> some View {
        modifier(BarBackground())
    }

    /// Semibold text with Increased Contrast; unchanged otherwise.
    func contrastEmphasis() -> some View {
        modifier(ContrastEmphasis())
    }
}

private struct ContrastOutline: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.overlay {
            if contrast == .increased {
                Circle().strokeBorder(Color(nsColor: .labelColor), lineWidth: 1)
            }
        }
    }
}

private struct ContrastBorder: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.overlay {
            if contrast == .increased {
                RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.separator)
            }
        }
    }
}

private struct BarBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .windowBackgroundColor))
        } else {
            content.background(.bar)
        }
    }
}

private struct ContrastEmphasis: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.fontWeight(contrast == .increased ? .semibold : nil)
    }
}
