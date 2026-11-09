import Foundation

/// The redesign's colors (docs/design/redesign-2026-11: Main and MainDark,
/// #70), the only place they are written down. Views ask for a token; the
/// app turns each into a color that follows the system's appearance and
/// Increased Contrast.
public enum Palette {
    public enum Token: CaseIterable, Sendable {
        case window, sidebar, sidebarSelection, sidebarBorder, separator, inspector
        case text, secondaryText, footerText
        case accent
        /// The Now card's fill, border and "NOW" label.
        case nowTint, nowBorder, nowLabel
        /// A selected task row.
        case selectedRow
        /// The grey count pills in the sidebar.
        case badge, badgeText
        case buttonBackground, buttonBorder
        /// Status dots.
        case green, amber, idleDot
        /// "WAITING ON YOU" and "Results ready" on In flight.
        case amberText, greenText
    }

    public struct RGB: Equatable, Sendable {
        public var red: Double, green: Double, blue: Double

        init(_ hex: UInt32) {
            red = Double((hex >> 16) & 0xff) / 255
            green = Double((hex >> 8) & 0xff) / 255
            blue = Double(hex & 0xff) / 255
        }

        /// "#0b63ce".
        public var hex: String {
            String(format: "#%02x%02x%02x", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
        }

        /// The WCAG contrast ratio between two colors, from 1 to 21.
        public func contrast(with other: RGB) -> Double {
            let (a, b) = (luminance, other.luminance)
            return (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }

        private var luminance: Double {
            func linear(_ value: Double) -> Double {
                value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
    }

    public static func color(_ token: Token, dark: Bool, increasedContrast: Bool = false) -> RGB {
        if increasedContrast, let stronger = (dark ? increasedDark : increasedLight)[token] {
            return RGB(stronger)
        }
        let (light, darkValue) = values[token]!
        return RGB(dark ? darkValue : light)
    }

    /// Light and dark, from the boards.
    private static let values: [Token: (UInt32, UInt32)] = [
        .window: (0xffffff, 0x1c1c1e),
        .sidebar: (0xf3f3f5, 0x232326),
        .sidebarSelection: (0xdedee3, 0x3a3a40),
        .sidebarBorder: (0xdcdce0, 0x38383d),
        .separator: (0xe5e5ea, 0x38383d),
        .inspector: (0xfafafa, 0x202023),
        .text: (0x1d1d1f, 0xf2f2f4),
        .secondaryText: (0x6e6e73, 0xa1a1a8),
        .footerText: (0x3a3a3c, 0xc7c7cc),
        .accent: (0x0b63ce, 0x2a74d6),
        .nowTint: (0xf3f6fb, 0x1f2a3c),
        .nowBorder: (0xd9e3f3, 0x2f4262),
        .nowLabel: (0x3b5b8c, 0x8db4ec),
        .selectedRow: (0xeef2f8, 0x2b2f38),
        .badge: (0x6e6e73, 0xb0b0b6),
        .badgeText: (0xffffff, 0x1c1c1e),
        .buttonBackground: (0xffffff, 0x2c2c30),
        .buttonBorder: (0xd1d1d6, 0x4a4a50),
        .green: (0x1f9d55, 0x1f9d55),
        .amber: (0xc77d00, 0xc77d00),
        .idleDot: (0xaeaeb2, 0x8e8e93),
        .amberText: (0x8a4b00, 0xe0a458),
        .greenText: (0x1f6b3a, 0x7fd79c),
    ]

    /// Increased Contrast: darker (or lighter) text, borders and selection;
    /// every other token keeps its color.
    private static let increasedLight: [Token: UInt32] = [
        .text: 0x000000, .secondaryText: 0x3a3a3c, .footerText: 0x1d1d1f,
        .sidebarSelection: 0xc7c7cc, .sidebarBorder: 0x8e8e93, .separator: 0x8e8e93, .buttonBorder: 0x6e6e73,
        .badge: 0x3a3a3c, .nowLabel: 0x1f3a63, .amberText: 0x6b3a00, .greenText: 0x14522b,
    ]
    private static let increasedDark: [Token: UInt32] = [
        .text: 0xffffff, .secondaryText: 0xd1d1d6, .footerText: 0xe5e5ea,
        .sidebarSelection: 0x4a4a50, .sidebarBorder: 0x8e8e93, .separator: 0x8e8e93, .buttonBorder: 0x98989f,
        .badge: 0xe5e5ea, .nowLabel: 0xb5cff5,
    ]
}
