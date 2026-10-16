import FocusPilotCore
import SwiftUI

/// "+ → From Herdr…": the workspaces of the local Herdr session, each ticked
/// to become a linked project. Workspaces that already have a project are
/// shown but cannot be ticked.
struct HerdrImportSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import from Herdr")
                    .font(.headline)
                Text("Each workspace you tick becomes a project linked to it. FocusPilot only reads Herdr.")
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            Divider()
            content
                .frame(height: 300)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(chosen.count > 1 ? "Import \(chosen.count) Projects" : "Import Project") { importChosen() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(chosen.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 520)
    }

    @ViewBuilder private var content: some View {
        if case .connected(let server, let workspaces) = model.herdr {
            let rows = HerdrImportRow.rows(for: workspaces, on: server, projects: model.projects)
            if rows.isEmpty {
                ContentUnavailableView("No workspaces", systemImage: "square.stack.3d.up",
                                       description: Text("Herdr has no open workspaces."))
            } else {
                List(rows) { row in
                    Toggle(isOn: binding(for: row)) {
                        HerdrWorkspaceLabel(workspace: row.workspace, note: note(for: row))
                    }
                    .disabled(!row.canImport)
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            }
        } else {
            HerdrUnavailableView(connection: model.herdr)
        }
    }

    private func note(for row: HerdrImportRow) -> String? {
        if let title = row.linkedProjectTitle { return "Already linked to “\(title)”" }
        if row.workspace.isLinkedWorktree { return "Agent worktree" }
        return nil
    }

    private func binding(for row: HerdrImportRow) -> Binding<Bool> {
        Binding(
            get: { !row.canImport || chosen.contains(row.id) },
            set: { isOn in
                if isOn { chosen.insert(row.id) } else { chosen.remove(row.id) }
            }
        )
    }

    private func importChosen() {
        guard case .connected(let server, let workspaces) = model.herdr else { return }
        let picked = workspaces.filter { chosen.contains($0.id) }
        Task {
            await model.importHerdrWorkspaces(picked, on: server)
            dismiss()
        }
    }
}

/// A workspace's label, with its checkout folder and an optional note
/// beneath.
struct HerdrWorkspaceLabel: View {
    let workspace: HerdrWorkspace
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(workspace.label)
            let details = [workspace.cwd.map(abbreviatingHome), note].compactMap(\.self)
            if !details.isEmpty {
                Text(details.joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func abbreviatingHome(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}

/// The honest reason no workspaces can be shown.
struct HerdrUnavailableView: View {
    let connection: HerdrConnection?

    var body: some View {
        switch connection {
        case nil, .connected:
            ProgressView()
        case .disconnected(let reason):
            ContentUnavailableView(reason.title, systemImage: "bolt.horizontal.circle",
                                   description: Text(reason.explanation))
        }
    }
}

extension HerdrUnavailable {
    var title: String {
        switch self {
        case .binaryNotFound: "Herdr not found"
        case .notRunning: "Herdr isn’t running"
        case .unsupportedVersion: "Herdr version not supported"
        case .unreadableReply: "Herdr’s reply wasn’t understood"
        }
    }

    var explanation: String {
        switch self {
        case .binaryNotFound:
            "FocusPilot looks for herdr in ~/.local/bin, /opt/homebrew/bin, /usr/local/bin and ~/.cargo/bin."
        case .notRunning:
            "Start Herdr and its workspaces appear here. FocusPilot checks again every few seconds."
        case .unsupportedVersion:
            "FocusPilot works with Herdr’s protocol 22 (Herdr 0.9). FocusPilot checks again every few seconds."
        case .unreadableReply:
            "This Herdr version may be newer than FocusPilot supports. FocusPilot checks again every few seconds."
        }
    }
}
