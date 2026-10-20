import SwiftUI

/// FocusPilot › Settings… (⌘,) opens Settings in the planning window
/// (design 07) rather than a separate Settings window.
struct SettingsCommand: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                model.requestedPage = .settings
                openWindow(id: PlanningView.windowID)
                NSApplication.shared.activate()
            }
            .keyboardShortcut(",")
        }
    }
}
