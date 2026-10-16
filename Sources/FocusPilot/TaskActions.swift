import FocusPilotCore
import SwiftUI

/// What the Task menu can do in the focused planning list.
struct TaskActions {
    enum Move {
        case now, next, later, up, down
    }

    /// The move the selected task allows, or nil if there is no selection
    /// or the move would change nothing.
    let placement: (Move) -> (id: Int64, status: TaskStatus, placement: TaskPlacement)?
    let perform: (Move) -> Void
}

extension FocusedValues {
    @Entry var taskActions: TaskActions?
    /// Opens the capture sheet. Published by the planning window itself, so
    /// ⌘N works even when no task list is shown (first launch, Projects
    /// with no projects).
    @Entry var quickCapture: (() -> Void)?
}

/// The Task menu (design 09). Start Focus, Pause, Complete and Open Context
/// arrive with their tickets.
struct TaskCommands: Commands {
    @FocusedValue(\.taskActions) private var actions
    @FocusedValue(\.quickCapture) private var quickCapture

    var body: some Commands {
        CommandMenu("Task") {
            Button("Quick Capture") { quickCapture?() }
                .keyboardShortcut("n")
                .disabled(quickCapture == nil)
            Divider()
            item("Make Current (Now)", .now, KeyboardShortcut("1"))
            item("Move to Next", .next, KeyboardShortcut("2"))
            item("Move to Later", .later, KeyboardShortcut("3"))
            item("Move Up", .up, KeyboardShortcut(.upArrow, modifiers: [.command, .option]))
            item("Move Down", .down, KeyboardShortcut(.downArrow, modifiers: [.command, .option]))
        }
    }

    private func item(_ title: String, _ move: TaskActions.Move, _ shortcut: KeyboardShortcut) -> some View {
        Button(title) { actions?.perform(move) }
            .keyboardShortcut(shortcut)
            .disabled(actions?.placement(move) == nil)
    }
}
