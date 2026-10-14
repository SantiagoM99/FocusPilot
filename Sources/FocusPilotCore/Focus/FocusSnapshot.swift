/// An immutable picture of FocusCoordinator state for the UI to display.
public struct FocusSnapshot: Equatable, Sendable {
    public var currentTaskTitle: String?

    public init(currentTaskTitle: String? = nil) {
        self.currentTaskTitle = currentTaskTitle
    }

    public var menuBarTitle: String {
        currentTaskTitle ?? "No current task"
    }
}
