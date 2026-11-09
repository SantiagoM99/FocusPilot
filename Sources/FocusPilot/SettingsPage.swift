import FocusPilotCore
import SwiftUI

/// Settings in the planning window (redesign Settings.dc.html). The tabs sit
/// in the page header; Second in command is phase 2 and not shown.
struct SettingsPage: View {
    enum Tab: String, CaseIterable {
        case blocking = "Blocking", chrome = "Chrome", observe = "Observe", general = "General"
    }

    let model: AppModel
    let tab: Tab

    var body: some View {
        Group {
            switch tab {
            case .blocking: BlockingSettings(model: model)
            case .chrome: ChromeSettings(model: model)
            case .observe: ObserveSettings(model: model)
            case .general: GeneralSettings(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await model.loadRules() }
    }
}

/// The segmented tabs in the Settings header.
struct SettingsTabs: View {
    @Binding var selection: SettingsPage.Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SettingsPage.Tab.allCases, id: \.self) { tab in
                if tab != SettingsPage.Tab.allCases.first {
                    Rectangle().fill(Color.palette(.buttonBorder)).frame(width: 1, height: 26)
                }
                Button { selection = tab } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: selection == tab ? .semibold : .regular))
                        .foregroundStyle(.palette(.text))
                        .padding(.horizontal, 14)
                        .frame(height: 26)
                        .background(selection == tab ? Color.palette(.sidebarSelection) : Color.palette(.buttonBackground))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.palette(.buttonBorder)))
    }
}

/// An error line under a settings table.
struct SettingsError: View {
    let message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }
}
