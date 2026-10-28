import FocusPilotCore
import SwiftUI

/// Protection status (design 03 and 04, #17): Browsers, then Safari, then
/// Apps, each its own fact. Nothing here sums them up as "protected".
/// While observing (#21) nothing is blocked, and that is all it says.
struct ProtectionStatusView: View {
    let model: AppModel
    var showsDetail = true
    var showsSafari = true
    var showsWeek = true

    var body: some View {
        if model.snapshot.isObserveOnly {
            ObservingLine(model: model, showsWeek: showsWeek)
        } else {
            lines
        }
    }

    private var lines: some View {
        VStack(alignment: .leading, spacing: 6) {
            BrowserStatusLine(status: model.browserProtection, showsDetail: showsDetail)
            if showsSafari {
                StatusLine(model.browserProtection.safari, symbol: "questionmark.circle", color: .secondary)
            }
            AppProtectionLine(text: model.appProtection)
        }
    }
}

struct BrowserStatusLine: View {
    let status: BrowserProtection
    var showsDetail = true

    var body: some View {
        StatusLine(status.line, detail: showsDetail ? status.detail : nil, symbol: status.level.symbol, color: status.level.color)
    }
}

/// An SF Symbol in the status color, the line, and an optional detail below.
struct StatusLine: View {
    let text: String
    let detail: String?
    let symbol: String
    let color: Color

    init(_ text: String, detail: String? = nil, symbol: String, color: Color) {
        self.text = text
        self.detail = detail
        self.symbol = symbol
        self.color = color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label {
                Text(text)
            } icon: {
                Image(systemName: symbol).foregroundStyle(color)
            }
            .font(.callout)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 22)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension BrowserProtection.Level {
    /// Design Spec: green only for full protection; unknown is never filled.
    var color: Color {
        switch self {
        case .protected: .green
        case .syncing, .degraded: .orange
        case .unknown: .secondary
        }
    }

    var symbol: String {
        switch self {
        case .protected: "shield.fill"
        case .syncing: "arrow.triangle.2.circlepath"
        case .degraded: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.circle"
        }
    }
}

/// The planning window's sidebar footer (design 01): "Chrome · Protected"
/// over "Apps · protected while running".
struct SidebarProtectionFooter: View {
    let model: AppModel

    var body: some View {
        let browsers = model.browserProtection
        let apps = model.appProtection
        VStack(alignment: .leading, spacing: 4) {
            if model.snapshot.isObserveOnly {
                // Design 12: a hollow gray dot, never green.
                footerLine("Observing · nothing is blocked", color: .secondary, hollow: true)
            } else {
                footerLine(browsers.footer, color: browsers.level.color, hollow: browsers.level == .unknown)
                footerLine(apps.short, color: apps.isProtected ? .green : .secondary, hollow: !apps.isProtected)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(browsers.detail ?? browsers.line)
    }

    private func footerLine(_ text: String, color: Color, hollow: Bool) -> some View {
        HStack(spacing: 6) {
            Group {
                if hollow { Circle().strokeBorder(color, lineWidth: 1) } else { Circle().fill(color) }
            }
            .frame(width: 7, height: 7)
            Text(text)
        }
    }
}
