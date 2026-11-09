import SwiftUI

/// One process: a menu-bar item plus the planning window. `LSUIElement` in
/// Info.plist keeps it out of the Dock.
@main
struct FocusPilotApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            MenuBarIcon(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Planning", id: PlanningView.windowID) {
            PlanningView(model: model)
        }
        // The redesign (#70) has no title bar: the window's buttons sit over the sidebar.
        .windowStyle(.hiddenTitleBar)
        // Login launches should not open a window; the menu bar item is the
        // entry point. The first launch is the exception (see MenuBarIcon).
        .defaultLaunchBehavior(.suppressed)
        .commands {
            TaskCommands(model: model)
            SettingsCommand(model: model)
        }
    }
}
