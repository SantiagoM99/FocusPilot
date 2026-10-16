import FocusPilotCore
import SwiftUI

/// Projects and, for the selected one, its tasks in the same list as Today
/// (design 15). Pinning a task here changes the one global Now.
struct ProjectsView: View {
    let model: AppModel
    let capture: () -> Void
    @State private var projectSelection: ProjectSummary.ID?
    @State private var taskSelection: Int64?

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 0) {
                List(model.projects, selection: $projectSelection) { project in
                    ProjectRow(project: project, now: context.date)
                }
                .frame(width: 280)
                Divider()
                detail(now: context.date)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: projectSelection) {
            taskSelection = nil
            if let projectSelection { Task { await model.showProject(projectSelection) } }
        }
        .onAppear {
            // Open on the project of the Now task, else the first one.
            let nowProject = model.today.first { $0.status == .now }?.projectTitle
            projectSelection = projectSelection
                ?? (model.projects.first { $0.title == nowProject } ?? model.projects.first)?.id
        }
    }

    @ViewBuilder
    private func detail(now: Date) -> some View {
        if let projectSelection, let project = model.projects.first(where: { $0.id == projectSelection }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(project.title)
                        .font(.title3.weight(.semibold))
                    Text(project.headline(at: now))
                        .foregroundStyle(project.isOverdue(at: now) ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                Divider()
                TaskList(items: model.projectItems, showsProject: false,
                         nowCaption: "the one current action, shared with Today", showsEmptyNow: false,
                         nextCaption: "Manual order within the project",
                         move: { id, status, placement in Task { await model.move(id, to: status, placement) } },
                         capture: capture, selection: $taskSelection)
            }
        } else if model.projects.isEmpty {
            ContentUnavailableView("No projects yet", systemImage: "folder",
                                   description: Text("Choose a project when you capture a task."))
        } else {
            ContentUnavailableView("Select a project", systemImage: "folder")
        }
    }
}

/// "NLP report" over "3 tasks · Due Sat 17 Oct", red when overdue.
private struct ProjectRow: View {
    let project: ProjectSummary
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(project.title)
            Text(project.detail(at: now))
                .font(.callout)
                .foregroundStyle(project.isOverdue(at: now) ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
        }
        .padding(.vertical, 4)
    }
}
