import SwiftUI

/// The redesign's buttons: outlined, or filled with the accent for the one
/// primary action on a surface.
struct PaletteButtonStyle: ButtonStyle {
    enum Kind {
        case primary, secondary
    }

    var kind = Kind.secondary
    var height: CGFloat = 28
    var cornerRadius: CGFloat = 6
    var fontSize: CGFloat = 13
    var horizontalPadding: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(style: self, configuration: configuration)
    }

    private struct StyledLabel: View {
        let style: PaletteButtonStyle
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: style.fontSize, weight: style.kind == .primary ? .semibold : .regular))
                .foregroundStyle(style.kind == .primary ? Color.white : Color.palette(.text))
                .padding(.horizontal, style.horizontalPadding)
                .frame(height: style.height)
                .background(style.kind == .primary ? Color.palette(.accent) : Color.palette(.buttonBackground),
                            in: RoundedRectangle(cornerRadius: style.cornerRadius))
                .overlay {
                    if style.kind == .secondary {
                        RoundedRectangle(cornerRadius: style.cornerRadius).strokeBorder(Color.palette(.buttonBorder))
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: style.cornerRadius))
                .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
        }
    }
}

extension ButtonStyle where Self == PaletteButtonStyle {
    static var palette: PaletteButtonStyle { PaletteButtonStyle() }
    static var palettePrimary: PaletteButtonStyle { PaletteButtonStyle(kind: .primary) }
}
