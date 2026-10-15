/// An immutable picture of FocusCoordinator state for the UI to display.
public struct FocusSnapshot: Equatable, Sendable {
    /// SF Symbol used inside the app where the custom glyph is not drawn yet
    /// (logo design 2d). The menu bar uses `MenuBarGlyph` instead.
    public static let fallbackSymbolName = "scope"

    public var currentTaskTitle: String?
    /// The latest session, which may have ended; `nil` before the first one.
    public var session: FocusSession?
    /// Observe-only mode measures without blocking (P0, ticket T13).
    public var isObserveOnly: Bool

    public init(currentTaskTitle: String? = nil, session: FocusSession? = nil, isObserveOnly: Bool = false) {
        self.currentTaskTitle = currentTaskTitle
        self.session = session
        self.isObserveOnly = isObserveOnly
    }

    /// The session that is still running, paused or on a break.
    public var activeSession: FocusSession? {
        guard let session, !session.hasEnded else { return nil }
        return session
    }

    /// The state line shown inside the menu and the planning window.
    public var statusText: String {
        activeSession?.action ?? currentTaskTitle ?? "No current task"
    }
}
