import FocusPilotCore
import SwiftUI

/// The task inspector (redesign Main, #71): the task, its deadline, next
/// action and workspace, its resources and Herdr agents, then Pin to Now and
/// Done. Nothing here acts on its own; focusing a pane happens only when the
/// owner clicks Open agent. Folders are revalidated each time it loads.
struct TaskInspector: View {
    let model: AppModel
    let task: TodayItem
    var showReviewQueue: () -> Void
    @State private var context: TaskContext?
    @State private var isLinkingResource = false
    @State private var isLinkingAgent = false

    private var links: [TaskAgentLink] { model.agentLinks.filter { $0.taskID == task.id } }

    /// The Herdr workspace linked to the task's project, if any.
    private var workspaceLink: HerdrLink? {
        task.projectID.flatMap { id in model.projects.first { $0.id == id }?.herdrLink }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    heading
                    TimelineView(.everyMinute) { details(now: $0.date) }
                    resources
                    agents
                }
                .padding(EdgeInsets(top: 22, leading: 20, bottom: 12, trailing: 20))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            pinAndDone
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity)
        .background { Color.palette(.inspector) }
        .overlay(alignment: .leading) { Rectangle().fill(Color.palette(.separator)).frame(width: 1) }
        .sheet(isPresented: $isLinkingResource) { LinkResourceSheet(model: model, task: task) }
        .sheet(isPresented: $isLinkingAgent) { AgentLinkSheet(model: model, task: task) }
        .task(id: "\(task.id)-\(model.contextRevision)-\(model.agentLinks.count)") {
            context = await model.context(forTask: task.id)
        }
        .onChange(of: task.id) { model.agentNotice = nil }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.palette(.text))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let project = task.projectTitle {
                Text(verbatim: project)
                    .font(.system(size: 12))
                    .foregroundStyle(.palette(.secondaryText))
            }
        }
    }

    private func details(now: Date) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 12) {
            GridRow {
                detailLabel("Deadline")
                deadlineValue(now: now)
            }
            GridRow {
                detailLabel("Next action")
                detailValue(task.nextAction)
                    .textSelection(.enabled)
            }
            GridRow {
                detailLabel("Workspace")
                workspaceValue
            }
        }
        .font(.system(size: 13))
    }

    private func detailLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.palette(.secondaryText))
            .frame(width: 84, alignment: .leading)
    }

    private func detailValue(_ text: String?) -> some View {
        Text(verbatim: text ?? "None")
            .foregroundStyle(.palette(text == nil ? .secondaryText : .text))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func deadlineValue(now: Date) -> some View {
        if let deadline = task.deadline {
            let text = DeadlineText(deadline)
            Text(text.dayAndTime(at: now))
                .foregroundStyle(deadline.isOverdue(at: now) ? Color.red : Color.palette(.text))
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(text.inspection)
                .accessibilityLabel(text.spoken(at: now))
        } else {
            detailValue(nil)
        }
    }

    // MARK: Workspace

    private var workspaceIsMissing: Bool {
        guard let link = workspaceLink, let herdr = model.herdr else { return false }
        return HerdrLinkState(link, herdr) == .notFound
    }

    @ViewBuilder private var workspaceValue: some View {
        let path = TaskInspection.workspace(herdr: workspaceLink, resources: context?.resources ?? [])
        if let link = workspaceLink, let projectID = task.projectID {
            let position = context?.launchSet.firstIndex(of: .workspace(projectID))
            InspectorRow(menuLabel: "More for the \(link.label) workspace", showsMenu: workspaceIsMissing) {
                VStack(alignment: .leading, spacing: 2) {
                    folderPath(path ?? link.label)
                    if workspaceIsMissing {
                        Text("Not found in Herdr")
                            .font(.system(size: 12))
                            .foregroundStyle(.palette(.amber))
                    }
                }
            } items: {
                LaunchItems(model: model, task: task, item: .workspace(projectID), position: position)
            }
        } else if let path {
            folderPath(path)
        } else {
            detailValue(nil)
        }
    }

    private func folderPath(_ path: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundStyle(.palette(.secondaryText))
                .accessibilityHidden(true)
            Text(verbatim: path)
                .foregroundStyle(.palette(.text))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(path)
        }
    }

    // MARK: Resources

    private var resources: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SectionTitle("Resources")
                Spacer()
                Button { Task { await model.openContext(forTask: task.id) } } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .disabled(context?.launchSet.isEmpty ?? true)
                .help(launchNames.isEmpty ? "Open context" : "Open context: " + launchNames.joined(separator: ", then "))
                .accessibilityLabel("Open context")
                Button { isLinkingResource = true } label: {
                    Image(systemName: "plus")
                }
                .help("Link resource")
                .accessibilityLabel("Link resource")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.palette(.secondaryText))
            .controlSize(.small)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(context?.resources ?? []) { status in
                    ResourceLinkRow(model: model, task: task, status: status,
                                    position: context?.launchSet.firstIndex(of: .resource(status.id)))
                }
            }
            if let notice = model.contextNotice, !model.contextNoticeOnNowCard {
                Text(notice)
                    .font(.system(size: 12))
                    .foregroundStyle(.palette(.secondaryText))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The launch set's names in order, for Open context's tooltip.
    private var launchNames: [String] {
        guard let context else { return [] }
        return context.launchSet.compactMap { item in
            switch item {
            case .resource(let id): context.resources.first { $0.id == id }?.resource.name
            case .agent(let id): context.agents.first { $0.id == id }.map { "\($0.label) in Herdr" }
            case .workspace: workspaceLink.map { "the \($0.label) workspace in Herdr" }
            }
        }
    }

    // MARK: Agents

    private var agents: some View {
        VStack(alignment: .leading, spacing: 8) {
            if links.isEmpty {
                HStack {
                    Text("Herdr agent")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.palette(.text))
                    Spacer()
                    Button("Link Agent…") { isLinkingAgent = true }
                        .buttonStyle(PaletteButtonStyle(height: 26, fontSize: 12, horizontalPadding: 10))
                }
                .agentCard()
            }
            ForEach(links) { link in
                AgentCard(model: model, link: link, title: links.count == 1 ? "Herdr agent" : link.label,
                          reviews: model.reviewItems.filter { $0.linkID == link.id }.map(\.kind),
                          linkAnother: { isLinkingAgent = true }, showReviewQueue: showReviewQueue)
            }
            if let notice = model.agentNotice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.palette(.amber))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Pin to Now and Done

    private var pinAndDone: some View {
        HStack(spacing: 8) {
            Button { Task { await model.move(task.id, to: .now, .top) } } label: {
                Text("Pin to Now").frame(maxWidth: .infinity)
            }
            .disabled(task.status == .now)
            Button { Task { await model.completeTask(task.id) } } label: {
                Text("Done").frame(maxWidth: .infinity)
            }
            .disabled(task.id == model.snapshot.activeSession?.taskID)
        }
        .buttonStyle(.palette)
        .padding(EdgeInsets(top: 10, leading: 20, bottom: 20, trailing: 20))
    }
}

/// A row whose actions sit in a "…" menu that appears on hover (or always,
/// when the row needs repair), and in its right-click menu and VoiceOver
/// actions, so the column stays as plain as the board draws it.
private struct InspectorRow<Content: View, Items: View>: View {
    let menuLabel: String
    var showsMenu = false
    @ViewBuilder var content: Content
    @ViewBuilder var items: Items
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            content
            Spacer(minLength: 0)
            Menu { items } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .opacity(isHovering || showsMenu ? 1 : 0)
                .accessibilityLabel(menuLabel)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu { items }
        .accessibilityActions { items }
    }
}

/// Whether Open context opens this item, and in what order.
private struct LaunchItems: View {
    let model: AppModel
    let task: TodayItem
    let item: ContextItem
    let position: Int?

    var body: some View {
        Button(position == nil ? "Add to Open Context" : "Remove from Open Context") {
            Task { await model.setLaunch(item, included: position == nil) }
        }
        if position ?? 0 > 0 {
            Button("Open Earlier") { Task { await model.moveEarlier(item, forTask: task.id) } }
        }
    }
}

/// A resource as a link: the dot and name, what is wrong with it if
/// anything, and repair and launch set actions in its menu.
private struct ResourceLinkRow: View {
    let model: AppModel
    let task: TodayItem
    let status: ResourceStatus
    let position: Int?

    private var resource: ContextResource { status.resource }

    private var problem: FolderProblem? {
        if case .needsRepair(let problem)? = status.folder { problem } else { nil }
    }

    /// A status worth a line of its own: broken, or followed to a new place.
    private var statusLine: String? {
        if let problem { return "Needs repair · " + ResourceText.problem(problem) }
        if case .moved(let path, _)? = status.folder { return ResourceText.moved(to: path) }
        return nil
    }

    private var details: String {
        var parts: [String] = []
        switch (resource.target, status.folder) {
        case (.folder, .healthy(let path)?): parts.append(ResourceText.path(path))
        case (.webPage(let page), _): parts += [page.url, ResourceText.sessionNote(for: page, rules: model.ruleSets)]
        default: break
        }
        if status.isFromProject { parts.append("All tasks in \(task.projectTitle ?? "the project")") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        InspectorRow(menuLabel: "More for \(resource.name)", showsMenu: problem != nil) {
            VStack(alignment: .leading, spacing: 2) {
                Button { model.openResource(status) } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.palette(problem == nil ? .accent : .amber))
                            .frame(width: 6, height: 6)
                            .contrastOutline()
                            .accessibilityHidden(true)
                        Text(verbatim: resource.name)
                            .font(.system(size: 13))
                            .foregroundStyle(.palette(.accent))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(problem != nil)
                .help(details)
                if let statusLine {
                    Text(verbatim: statusLine)
                        .font(.system(size: 12))
                        .foregroundStyle(.palette(problem == nil ? .secondaryText : .amber))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 14)
                }
            }
        } items: {
            if let problem {
                Button("Relink…") {
                    Task { await model.relinkFolder(resource.id, near: resource.folderBookmark?.path ?? NSHomeDirectory()) }
                }
                if case .replaced = problem {
                    Button("Use This Folder") { Task { await model.useFolderNowAtPath(resource.id) } }
                }
                Divider()
            }
            LaunchItems(model: model, task: task, item: .resource(resource.id), position: position)
            Divider()
            Button("Unlink", role: .destructive) { Task { await model.unlinkResource(resource.id) } }
        }
    }
}

/// One linked Herdr agent: its status, Review while something waits, Open
/// agent, and Relink when it was renamed; the rest is in the "…" menu.
private struct AgentCard: View {
    let model: AppModel
    let link: TaskAgentLink
    let title: String
    let reviews: [AgentTransition.Review]
    var linkAnother: () -> Void
    var showReviewQueue: () -> Void
    @State private var isHovering = false

    var body: some View {
        let state = AgentLinkState(link, model.herdrAgents)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.palette(.text))
                    .lineLimit(1)
                Spacer(minLength: 0)
                AgentStatusDot(status: AgentCardStatus(state, pending: reviews))
            }
            HStack(spacing: 8) {
                if !reviews.isEmpty {
                    Button("Review", action: showReviewQueue)
                }
                Button("Open agent") { Task { await model.openAgent(link.id) } }
                    .disabled(!state.canOpen)
                if case .renamed = state {
                    Button("Relink") { Task { await model.relinkAgent(link.id) } }
                }
                Spacer(minLength: 0)
                Menu { items } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .opacity(isHovering ? 1 : 0)
                    .accessibilityLabel("More for \(link.label)")
            }
            .buttonStyle(PaletteButtonStyle(height: 26, fontSize: 12, horizontalPadding: 10))
        }
        .agentCard()
        .help(place)
        .onHover { isHovering = $0 }
        .contextMenu { items }
    }

    /// "Herdr · PhD › reviewer", and the agent's own title if it has one.
    private var place: String {
        var text = "Herdr · \(link.workspaceLabel ?? link.workspaceID) › \(link.label)"
        if case .live(let agent) = AgentLinkState(link, model.herdrAgents), let title = agent.title {
            text += "\n" + title
        }
        return text
    }

    @ViewBuilder private var items: some View {
        Button(link.launchOrder == nil ? "Add to Open Context" : "Remove from Open Context") {
            Task { await model.setLaunch(.agent(link.id), included: link.launchOrder == nil) }
        }
        Button("Link Another Agent…", action: linkAnother)
        Divider()
        Button("Unlink", role: .destructive) { Task { await model.unlinkAgent(link.id) } }
    }
}

private struct AgentStatusDot: View {
    let status: AgentCardStatus

    var body: some View {
        HStack(spacing: 6) {
            Group {
                switch status.tone {
                case .accent: Circle().fill(Color.palette(.accent))
                case .green: Circle().fill(Color.palette(.green))
                case .amber: Circle().fill(Color.palette(.amber))
                case .unknown: Circle().strokeBorder(Color.palette(.secondaryText), lineWidth: 1)
                }
            }
            .frame(width: 7, height: 7)
            .contrastOutline()
            .accessibilityHidden(true)
            Text(verbatim: status.title)
                .font(.system(size: 12))
                .foregroundStyle(.palette(status.tone == .green ? .greenText : .secondaryText))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension View {
    func agentCard() -> some View {
        padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.palette(.buttonBackground), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.palette(.separator)))
    }
}
