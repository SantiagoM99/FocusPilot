import FocusPilotCore
import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        @Bindable var preferences = model.menuBarPreferences
        Form {
            Toggle("Show time left in the menu bar", isOn: $preferences.showsTime)
            Toggle("Show the focus panel during sessions", isOn: $preferences.showsFocusPanel)
                .onChange(of: preferences.showsFocusPanel) { model.focusPanel.update() }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }
}
