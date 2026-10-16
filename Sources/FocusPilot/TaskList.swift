import FocusPilotCore
import SwiftUI

/// Now, Next and Later in the owner's manual order. Used by Today and,
/// filtered to one project, by Projects. Rows are reordered by dragging
/// within a section, or with the Task menu and context menu.
struct TaskList: View {
    let items: [TodayItem]
    let showsProject: Bool
    var nowCaption: String? = nil
    /// Today shows an empty Now card; a project whose tasks do not include
    /// the one Now leaves it out rather than claim there is none.
    var showsEmptyNow = true
    var nextCaption = "Manual order · drag to reorder"
    let move: (Int64, TaskStatus, TaskPlacement) -> Void
    let capture: () -> Void
    @Binding var selection: Int64?

    var body: some View {
        let sections = TaskSections(items)
        // Relative labels ("Due today 17:00", "Overdue …") change with time.
        TimelineView(.everyMinute) { context in
            List(selection: $selection) {
                if sections.now != nil || showsEmptyNow {
                    Section {
                        NowCard(item: sections.now, caption: nowCaption, showsProject: showsProject, now: context.date)
                            .tag(sections.now?.id)
                            .listRowSeparator(.hidden)
                    }
                }
                section(.next, "Next", caption: nextCaption, sections, context.date)
                section(.later, "Later", caption: nil, sections, context.date)
            }
            .listStyle(.inset)
            .contextMenu(forSelectionType: Int64.self) { ids in
                if let id = ids.first {
                    Button("Make Current (Now)") { perform(.now, on: id) }
                    Button("Move to Next") { perform(.next, on: id) }
                    Button("Move to Later") { perform(.later, on: id) }
                }
            }
        }
        .focusedSceneValue(\.taskActions, TaskActions(
            capture: capture,
            placement: { action in selection.flatMap { placement(for: action, of: $0) } },
            perform: { move in selection.map { perform(move, on: $0) } }
        ))
    }

    @ViewBuilder
    private func section(_ status: TaskStatus, _ title: String, caption: String?, _ sections: TaskSections,
                         _ now: Date) -> some View {
        let members = sections.items(in: status)
        if !members.isEmpty {
            Section {
                ForEach(members) { item in
                    TaskRow(item: item, showsProject: showsProject, now: now)
                }
                .onMove { offsets, destination in
                    guard let source = offsets.first else { return }
                    let ids = members.map(\.id)
                    if let placement = TaskPlacement.drop(ids[source], at: destination, in: ids) {
                        move(ids[source], status, placement)
                    }
                }
            } header: {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                    if let caption {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func perform(_ action: TaskActions.Move, on id: Int64) {
        if let target = placement(for: action, of: id) {
            move(target.id, target.status, target.placement)
        }
    }

    /// Moving into a section puts the task at its top, where it is seen;
    /// Move Up and Down stay within the section, among the visible rows.
    private func placement(for action: TaskActions.Move, of id: Int64)
        -> (id: Int64, status: TaskStatus, placement: TaskPlacement)? {
        guard let item = items.first(where: { $0.id == id }) else { return nil }
        let visible = TaskSections(items).items(in: item.status).map(\.id)
        switch action {
        case .now: return item.status == .now ? nil : (id, .now, .top)
        case .next: return (id, .next, .top)
        case .later: return (id, .later, .top)
        case .up: return TaskPlacement.up(id, in: visible).map { (id, item.status, $0) }
        case .down: return TaskPlacement.down(id, in: visible).map { (id, item.status, $0) }
        }
    }
}
