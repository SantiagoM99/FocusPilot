import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Closing the planning window must not quit: the menu bar item, and the
    // focus state behind it, stay alive until the owner chooses Quit.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
