import FocusPilotCore
import SwiftUI

/// Settings › General: menu bar and login.
struct GeneralSettings: View {
    let model: AppModel

    var body: some View {
        @Bindable var preferences = model.menuBarPreferences
        Form {
            Section("Menu bar") {
                Toggle("Show time left in the menu bar", isOn: $preferences.showsTime)
            }
            Section("General") {
                Toggle("Open at Login", isOn: Binding(
                    get: { model.loginItem.isEnabled },
                    set: { model.loginItem.setEnabled($0) }
                ))
                if let message = model.loginItem.errorMessage {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
