import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Closing the planning window must not quit: the menu bar item, and the
    // focus state behind it, stay alive until the owner chooses Quit.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // Opening the app again (Finder, Spotlight, or "Return to task" on
    // Chrome's blocked page) brings up the planning window with the task.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        NotificationCenter.default.post(name: .showPlanningWindow, object: nil)
        return false
    }
}

extension Notification.Name {
    static let showPlanningWindow = Notification.Name("FocusPilot.showPlanningWindow")
}
