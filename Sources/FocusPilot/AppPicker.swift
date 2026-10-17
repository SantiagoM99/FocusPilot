import AppKit
import FocusPilotCore
import UniformTypeIdentifiers

/// Lets the owner choose a Mac app from /Applications and returns it as a
/// target identified by its bundle ID.
@MainActor
enum AppPicker {
    static func choose() -> ActivityTarget? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        panel.message = "Choose an app"
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return .app(bundleID: bundleID, name: name)
    }
}
