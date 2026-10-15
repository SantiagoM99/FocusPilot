import FocusPilotCore
import SwiftUI

struct SettingsView: View {
    @Bindable var preferences: MenuBarPreferences

    var body: some View {
        Form {
            Toggle("Show time left in the menu bar", isOn: $preferences.showsTime)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }
}
