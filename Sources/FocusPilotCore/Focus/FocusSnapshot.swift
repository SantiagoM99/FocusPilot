/// An immutable picture of FocusCoordinator state for the UI to display.
public struct FocusSnapshot: Equatable, Sendable {
    /// The menu bar shows an icon, never text: macOS hides menu bar items
    /// behind the notch when the bar is crowded, and a long text item is the
    /// first to go, which makes the app look as if it had quit.
    public static let menuBarSymbolName = "scope"

    public var currentTaskTitle: String?

    public init(currentTaskTitle: String? = nil) {
        self.currentTaskTitle = currentTaskTitle
    }

    /// The state line shown inside the menu and the planning window.
    public var statusText: String {
        currentTaskTitle ?? "No current task"
    }

    /// What VoiceOver reads for the menu bar icon, which has no visible text.
    public var menuBarAccessibilityLabel: String {
        "FocusPilot: \(statusText)"
    }
}
