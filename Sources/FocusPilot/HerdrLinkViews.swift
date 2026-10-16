import FocusPilotCore
import SwiftUI

/// Under a project's title: its Herdr workspace and what can be done with
/// the link. A missing workspace never removes the project or its tasks.
struct HerdrLinkLine: View {
    let model: AppModel
    let project: ProjectSummary
    @State private var isLinking = false

    var body: some View {
        HStack(spacing: 8) {
            if let link = project.herdrLink {
                switch HerdrLinkState(link, model.herdr ?? .disconnected(.notRunning)) {
                case .live(let workspace):
                    Label("Herdr workspace “\(workspace.label)”", systemImage: "link")
                        .foregroundStyle(.secondary)
                case .notFound:
                    Label("Workspace “\(link.label)” not found in Herdr", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("Relink…") { isLinking = true }
                case .unknown:
                    Label("Herdr workspace “\(link.label)” · Herdr unavailable", systemImage: "link")
                        .foregroundStyle(.secondary)
                }
                Button("Unlink") { Task { await model.unlinkProject(project.id!) } }
            } else {
                Button("Link to Herdr Workspace…", systemImage: "link") { isLinking = true }
            }
        }
        .controlSize(.small)
        .buttonStyle(.link)
        .sheet(isPresented: $isLinking) {
            HerdrLinkSheet(model: model, project: project)
        }
    }
}

/// Links a project to one workspace, or relinks it after its workspace went
/// missing. A matching workspace is preselected, but nothing changes until
/// the owner confirms.
struct HerdrLinkSheet: View {
    let model: AppModel
    let project: ProjectSummary
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?

    private var isRelink: Bool { project.herdrLink != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isRelink ? "Relink “\(project.title)”" : "Link “\(project.title)” to Herdr")
                    .font(.headline)
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            Divider()
            content
                .frame(height: 260)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isRelink ? "Relink" : "Link") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
            .padding(20)
        }
        .frame(width: 520)
        .onAppear { selection = suggestion?.id }
    }

    private var subtitle: String {
        guard let link = project.herdrLink else {
            return "Choose the workspace this project's work happens in. FocusPilot only reads Herdr."
        }
        let match = suggestion.map { " “\($0.label)” has the same name and folder." } ?? ""
        return "The workspace “\(link.label)” is no longer in Herdr, possibly because Herdr restarted.\(match)"
    }

    /// Workspaces not linked to another project.
    private var available: [HerdrWorkspace] {
        guard case .connected(let server, let workspaces) = model.herdr else { return [] }
        return HerdrImportRow.rows(for: workspaces, on: server, projects: model.projects)
            .filter(\.canImport).map(\.workspace)
    }

    private var suggestion: HerdrWorkspace? {
        project.herdrLink.flatMap { HerdrRelink.suggestion(for: $0, among: available) }
    }

    @ViewBuilder private var content: some View {
        if case .connected = model.herdr {
            if available.isEmpty {
                ContentUnavailableView("No free workspaces", systemImage: "square.stack.3d.up",
                                       description: Text("Every open Herdr workspace is already linked to a project."))
            } else {
                List(available, selection: $selection) { workspace in
                    HerdrWorkspaceLabel(workspace: workspace,
                                        note: workspace == suggestion ? "Same name and folder" : nil)
                        .padding(.vertical, 2)
                }
                .listStyle(.inset)
            }
        } else {
            HerdrUnavailableView(connection: model.herdr)
        }
    }

    private func apply() {
        guard case .connected(let server, _) = model.herdr,
              let workspace = available.first(where: { $0.id == selection }), let id = project.id else { return }
        Task {
            await model.linkProject(id, to: workspace, on: server)
            dismiss()
        }
    }
}

/// The foot of the projects column: whether Herdr is reachable.
struct HerdrStatusLine: View {
    let connection: HerdrConnection?

    var body: some View {
        Group {
            switch connection {
            case nil:
                Text("Herdr: checking…")
            case .connected(_, let workspaces):
                Label(workspaces.count == 1 ? "Herdr: 1 workspace" : "Herdr: \(workspaces.count) workspaces",
                      systemImage: "circle.fill")
                    .labelStyle(StatusDotLabelStyle(color: .green))
            case .disconnected(let reason):
                Label("\(reason.title) · retrying", systemImage: "circle.fill")
                    .labelStyle(StatusDotLabelStyle(color: .gray))
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct StatusDotLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.system(size: 7))
                .foregroundStyle(color)
            configuration.title
        }
    }
}
