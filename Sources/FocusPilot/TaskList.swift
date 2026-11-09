import AppKit
import FocusPilotCore
import SwiftUI

/// Now, Next and Later in the owner's manual order. Used by Today and,
/// filtered to one project, by Projects. Rows are reordered by dragging
/// within a section, or with the Task menu and context menu.
struct TaskList: View {
    let items: [TodayItem]
    let showsProject: Bool
    /// Today shows an empty Now card; a project whose tasks do not include
    /// the one Now leaves it out rather than claim there is none.
    var showsEmptyNow = true
    let move: (Int64, TaskStatus, TaskPlacement) -> Void
    /// Removes a task added from Herdr; nil hides Undo.
    var undoHerdrAdd: ((Int64) -> Void)?
    /// Undo is not offered for the task a session is running on.
    var activeSessionTaskID: Int64?
    @Binding var selection: Int64?
    /// For Mark as waiting (#57); absent in previews.
    @Environment(AppModel.self) private var model: AppModel?

    /// A plain list indents row content 8 pt; with this it lands on the
    /// board's 24 pt margin.
    private static let rowInsets = EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)

    var body: some View {
        let sections = TaskSections(items)
        // Relative labels ("Due today 17:00", "Overdue …") change with time.
        TimelineView(.everyMinute) { context in
            List(selection: $selection) {
                if sections.now != nil || showsEmptyNow {
                    NowCard(item: sections.now, showsProject: showsProject, now: context.date)
                        .padding(.top, 22)
                        .tag(sections.now?.id)
                        .listRowInsets(Self.rowInsets)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                section(.next, "Next", sections, context.date)
                section(.later, "Later", sections, context.date)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background { Color.palette(.window) }
            .environment(\.defaultMinListRowHeight, 1)
            .contextMenu(forSelectionType: Int64.self) { ids in
                if let id = ids.first {
                    Button("Make Current (Now)") { perform(.now, on: id) }
                    Button("Move to Next") { perform(.next, on: id) }
                    Button("Move to Later") { perform(.later, on: id) }
                    if let model {
                        Divider()
                        Button(model.waiting(for: id) == nil ? "Mark as Waiting…" : "Change Waiting…") { model.markingWaiting = id }
                        if model.waiting(for: id) != nil {
                            Button("Stop Waiting") { Task { await model.stopWaiting(id) } }
                        }
                    }
                    if let undoHerdrAdd,
                       items.first(where: { $0.id == id })?.offersHerdrUndo(activeSessionTaskID: activeSessionTaskID) == true {
                        Divider()
                        Button("Undo Add from Herdr") { undoHerdrAdd(id) }
                    }
                }
            }
        }
        .focusedSceneValue(\.taskActions, TaskActions(
            placement: { action in selection.flatMap { placement(for: action, of: $0) } },
            perform: { move in selection.map { perform(move, on: $0) } }
        ))
    }

    @ViewBuilder
    private func section(_ status: TaskStatus, _ title: String, _ sections: TaskSections,
                         _ now: Date) -> some View {
        let members = sections.items(in: status)
        if !members.isEmpty {
            SectionTitle(title)
                .padding(EdgeInsets(top: 28, leading: 6, bottom: 6, trailing: 0))
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowInsets(Self.rowInsets)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            ForEach(members) { item in
                TaskRow(item: item, showsProject: showsProject, now: now, isSelected: selection == item.id,
                        undo: item.offersHerdrUndo(activeSessionTaskID: activeSessionTaskID)
                            ? undoHerdrAdd.map { undo in { undo(item.id) } } : nil)
                    .background(NoSystemRowHighlight())
                    .listRowInsets(Self.rowInsets)
                    .listRowSeparator(.hidden)
                    .listRowBackground(RoundedRectangle(cornerRadius: 6)
                        .fill(selection == item.id ? Color.palette(.selectedRow) : .clear)
                        .padding(.horizontal, 24))
            }
            .onMove { offsets, destination in
                guard let source = offsets.first else { return }
                let ids = members.map(\.id)
                if let placement = TaskPlacement.drop(ids[source], at: destination, in: ids) {
                    move(ids[source], status, placement)
                }
            }
        }
    }

    private func perform(_ action: TaskActions.Move, on id: Int64) {
        if let target = placement(for: action, of: id) {
            move(target.id, target.status, target.placement)
        }
    }

    /// Moving into a section puts the task at its top, where it is seen, and
    /// is unavailable when the task is already there. Move Up and Down stay
    /// within the section, among the visible rows.
    private func placement(for action: TaskActions.Move, of id: Int64)
        -> (id: Int64, status: TaskStatus, placement: TaskPlacement)? {
        guard let item = items.first(where: { $0.id == id }) else { return nil }
        let sections = TaskSections(items)
        let visible = sections.items(in: item.status).map(\.id)
        func toTop(_ status: TaskStatus) -> (id: Int64, status: TaskStatus, placement: TaskPlacement)? {
            TaskPlacement.toTop(of: status, moving: id, from: item.status, visible: visible).map { (id, status, $0) }
        }
        switch action {
        case .now: return toTop(.now)
        case .next: return toTop(.next)
        case .later: return toTop(.later)
        case .up: return TaskPlacement.up(id, in: visible).map { (id, item.status, $0) }
        case .down: return TaskPlacement.down(id, in: visible).map { (id, item.status, $0) }
        }
    }
}

/// The board tints the selected row in place of the system's accent bar.
/// SwiftUI has no API for that, so this turns the highlight off on the
/// table the row sits in; if AppKit's hierarchy changes, the system bar
/// simply comes back.
private struct NoSystemRowHighlight: NSViewRepresentable {
    final class Probe: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            var view = superview
            while let current = view {
                if let table = current as? NSTableView {
                    table.selectionHighlightStyle = .none
                    return
                }
                view = current.superview
            }
        }
    }

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) {}
}
