import FocusPilotCore
import SwiftUI

/// What the Task menu can do in the focused planning list.
struct TaskActions {
    enum Move {
        case now, next, later, up, down
    }

    let capture: () -> Void
    /// The move the selected task allows, or nil if there is no selection
    /// or the move would change nothing.
    let placement: (Move) -> (id: Int64, status: TaskStatus, placement: TaskPlacement)?
    let perform: (Move) -> Void
}

extension FocusedValues {
    @Entry var taskActions: TaskActions?
}

/// The Task menu (design 09). Start Focus, Pause, Complete and Open Context
/// arrive with their tickets.
struct TaskCommands: Commands {
    @FocusedValue(\.taskActions) private var actions

    var body: some Commands {
        CommandMenu("Task") {
            Button("Quick Capture") { actions?.capture() }
                .keyboardShortcut("n")
                .disabled(actions == nil)
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
