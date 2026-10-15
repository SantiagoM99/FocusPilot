import AppKit
import FocusPilotCore
import SwiftUI

struct MenuBarContent: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.snapshot.statusText)
        if let startupError = model.startupError {
            Text(startupError)
        }

        Divider()

        Button("Open Planning Window") {
            openWindow(id: PlanningView.windowID)
            // A menu-bar app is never frontmost on its own, so without this
            // the window would open behind the current app.
            NSApplication.shared.activate()
        }

        LoginItemToggle(settings: model.loginItem)

        Divider()

        Button("Quit FocusPilot") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

private struct LoginItemToggle: View {
    let settings: LoginItemSettings

    var body: some View {
        Toggle("Open at Login", isOn: Binding(
            get: { settings.isEnabled },
            set: { settings.setEnabled($0) }
        ))

        if settings.needsApproval {
            Button("Allow in System Settings…") {
                settings.openSystemSettings()
            }
        }
        if let errorMessage = settings.errorMessage {
            Text(errorMessage)
        }
    }
}
