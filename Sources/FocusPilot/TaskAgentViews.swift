import FocusPilotCore
import SwiftUI

struct AgentActivityLabel: View {
    let activity: AgentActivity

    var body: some View {
        switch activity {
        case .working: StatusDot(title: "Working", color: .accentColor, filled: true)
        case .blocked: StatusDot(title: "Blocked", color: .orange, filled: true)
        case .ready: StatusDot(title: "Ready", color: .green, filled: true)
        // Unknown is never shown as done.
        case .unknown: StatusDot(title: "Unknown", color: .gray, filled: false)
        }
    }
}

struct StatusDot: View {
    let title: String
    let color: Color
    let filled: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: filled ? "circle.fill" : "circle")
                .font(.system(size: 8))
                .foregroundStyle(color)
                .contrastOutline()
                .accessibilityHidden(true)
            Text(title)
                .font(.callout.weight(.medium))
        }
    }
}

extension AgentLinkState {
    var canOpen: Bool {
        if case .live = self { true } else { false }
    }
}

/// Chooses Herdr agents for a task. Agents in the task's project's
/// workspace come first, already ticked; nothing is linked until Link.
struct AgentLinkSheet: View {
    let model: AppModel
    let task: TodayItem
    @Environment(\.dismiss) private var dismiss
    @State private var agents: HerdrAgents?
    @State private var chosen: Set<String> = []

    private var choices: (server: HerdrServer, choices: AgentLinkChoices)? {
        guard case .connected(let server, let list)? = agents else { return nil }
        let projectLink = task.projectID.flatMap { id in model.projects.first { $0.id == id }?.herdrLink }
        return (server, AgentLinkChoices(list, on: server, projectLink: projectLink,
                                         linked: model.agentLinks.filter { $0.taskID == task.id }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "Link agents to “\(task.title)”")
                    .font(.headline)
            }
            .padding(20)
            Divider()
            content
                .frame(height: 280)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(chosen.count > 1 ? "Link \(chosen.count) Agents" : "Link Agent") { link() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(chosen.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 540)
        .task {
            agents = await model.availableAgents()
            chosen = choices?.choices.preselected ?? []
        }
    }

    @ViewBuilder private var content: some View {
        switch agents {
        case nil:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .disconnected(let reason):
            ContentUnavailableView(reason.title, systemImage: "bolt.horizontal.circle")
        case .connected:
            if let choices, !choices.choices.agents.isEmpty {
                List(choices.choices.agents) { agent in
                    Toggle(isOn: binding(for: agent.paneID)) {
                        AgentChoiceLabel(agent: agent, workspace: workspaceLabel(agent.workspaceID),
                                         inProject: choices.choices.preselected.contains(agent.paneID))
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            } else {
                ContentUnavailableView("No agents to link", systemImage: "terminal")
            }
        }
    }

    private func workspaceLabel(_ id: String) -> String {
        if case .connected(_, let workspaces)? = model.herdr, let match = workspaces.first(where: { $0.id == id }) {
            return match.label
        }
        return id
    }

    private func binding(for paneID: String) -> Binding<Bool> {
        Binding(get: { chosen.contains(paneID) },
                set: { if $0 { chosen.insert(paneID) } else { chosen.remove(paneID) } })
    }

    private func link() {
        guard let choices else { return }
        let picked = choices.choices.agents.filter { chosen.contains($0.paneID) }
        Task {
            await model.linkAgents(picked, on: choices.server, toTask: task.id)
            dismiss()
        }
    }
}

private struct AgentChoiceLabel: View {
    let agent: HerdrAgent
    let workspace: String
    let inProject: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(verbatim: agent.name ?? agent.kind)
                    .fontWeight(.medium)
                AgentActivityLabel(activity: agent.status.activity)
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: "\(workspace) · \(agent.kind) · \(agent.paneID)" + (inProject ? " · this task’s project" : ""))
                .font(.callout)
                .foregroundStyle(.secondary)
            if let title = agent.title {
                Text(verbatim: title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
