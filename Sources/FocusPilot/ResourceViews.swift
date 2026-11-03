import FocusPilotCore
import SwiftUI

/// The selected task's Resources section (design 01): linked folders and
/// pages with their state, which of them Open context opens, and repair
/// actions for broken links. Folders are revalidated each time it loads.
struct TaskResourcesSection: View {
    let model: AppModel
    let task: TodayItem
    @State private var context: TaskContext?
    @State private var isLinking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle("Resources")
                Spacer()
                Button("Link Resource…", systemImage: "plus") { isLinking = true }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .labelStyle(.iconOnly)
            }
            OpenContextButton(model: model, taskID: task.id, launchSet: context.map(launchNames) ?? [])
            if let context {
                if context.resources.isEmpty {
                    Text("No resources")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(context.resources) { status in
                    ResourceRowView(model: model, task: task, status: status,
                                    launchPosition: context.launchSet.firstIndex(of: .resource(status.id)))
                }
                if let projectID = task.projectID, let link = workspaceLink {
                    WorkspaceRowView(model: model, task: task, projectID: projectID, link: link,
                                     launchPosition: context.launchSet.firstIndex(of: .workspace(projectID)))
                }
            }
        }
        .sheet(isPresented: $isLinking) {
            LinkResourceSheet(model: model, task: task)
        }
        .task(id: "\(task.id)-\(model.contextRevision)-\(model.agentLinks.count)") {
            context = await model.context(forTask: task.id)
        }
    }

    /// The Herdr workspace linked to the task's project, if any.
    private var workspaceLink: HerdrLink? {
        task.projectID.flatMap { id in model.projects.first { $0.id == id }?.herdrLink }
    }

    /// The launch set's names in order, for the line under Open context.
    private func launchNames(_ context: TaskContext) -> [String] {
        context.launchSet.compactMap { item in
            switch item {
            case .resource(let id): context.resources.first { $0.id == id }?.resource.name
            case .agent(let id): context.agents.first { $0.id == id }.map { "\($0.label) in Herdr" }
            case .workspace: workspaceLink.map { "the \($0.label) workspace in Herdr" }
            }
        }
    }
}

/// Open context, with what it opens and what the last one did.
struct OpenContextButton: View {
    let model: AppModel
    let taskID: Int64
    let launchSet: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { Task { await model.openContext(forTask: taskID) } } label: {
                Label("Open context", systemImage: "arrow.up.forward.app")
            }
            .disabled(launchSet.isEmpty)
            if !launchSet.isEmpty {
                Text(verbatim: launchSet.joined(separator: ", then "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let notice = model.contextNotice, !model.contextNoticeOnNowCard {
                Text(notice)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ResourceRowView: View {
    let model: AppModel
    let task: TodayItem
    let status: ResourceStatus
    let launchPosition: Int?

    private var resource: ContextResource { status.resource }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(problem == nil ? Color.secondary : .orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: resource.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let path = shownPath {
                        Text(verbatim: path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(path)
                    }
                    if let detail {
                        Text(verbatim: detail)
                            .font(.caption)
                            .foregroundStyle(problem == nil ? .secondary : Color.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                // One item for VoiceOver: name, path and state, without the middle dots.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([resource.name, shownPath, detail?.replacing(" · ", with: ", ")]
                    .compactMap(\.self).joined(separator: ", "))
                Spacer(minLength: 0)
            }
            if let problem {
                repairActions(problem)
            }
            HStack {
                Toggle("Opens with context", isOn: Binding(
                    get: { launchPosition != nil },
                    set: { included in Task { await model.setLaunch(.resource(resource.id), included: included) } }))
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("\(resource.name) opens with context")
                if let launchPosition {
                    Text("· \(launchPosition + 1)")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("opens \(ordinal(launchPosition + 1))")
                }
                Spacer()
                Menu {
                    if launchPosition ?? 0 > 0 {
                        Button("Open Earlier") { Task { await model.moveEarlier(.resource(resource.id), forTask: task.id) } }
                    }
                    Button("Unlink", role: .destructive) { Task { await model.unlinkResource(resource.id) } }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More for \(resource.name)")
            }
            .font(.caption)
            .controlSize(.small)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
        .contrastBorder(cornerRadius: 8)
    }

    private var problem: FolderProblem? {
        if case .needsRepair(let problem)? = status.folder { problem } else { nil }
    }

    private var icon: String {
        switch resource.target {
        case .folder: problem == nil ? "folder" : "folder.badge.questionmark"
        case .webPage: "globe"
        }
    }

    /// A healthy folder's path, on one line.
    private var shownPath: String? {
        switch status.folder {
        case .healthy(let path)?: ResourceText.path(path)
        default: nil
        }
    }

    private var detail: String? {
        let scope = status.isFromProject ? "All tasks in \(task.projectTitle ?? "the project")" : nil
        switch (resource.target, status.folder) {
        case (_, .needsRepair(let problem)?):
            return "Needs repair · " + ResourceText.problem(problem)
        case (_, .moved(let path, _)?):
            return ([ResourceText.moved(to: path)] + [scope].compactMap { $0 }).joined(separator: " · ")
        case (.folder, _):
            return scope
        case (.webPage(let page), _):
            return (["Web page", ResourceText.sessionNote(for: page, rules: model.ruleSets)] + [scope].compactMap { $0 })
                .joined(separator: " · ")
        }
    }

    @ViewBuilder
    private func repairActions(_ problem: FolderProblem) -> some View {
        HStack(spacing: 8) {
            Button("Relink…") {
                Task { await model.relinkFolder(resource.id, near: resource.folderBookmark?.path ?? NSHomeDirectory()) }
            }
            if case .replaced = problem {
                Button("Use This Folder") { Task { await model.useFolderNowAtPath(resource.id) } }
            }
            Button("Unlink") { Task { await model.unlinkResource(resource.id) } }
                .buttonStyle(.link)
        }
        .controlSize(.small)
    }
}

/// "1st", "2nd" (VoiceOver says "first", "second"): the launch position,
/// in English whatever the system language, as the UI is English.
private func ordinal(_ number: Int) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.numberStyle = .ordinal
    return formatter.string(for: number) ?? "\(number)"
}

/// The project's Herdr workspace: Open context can focus its first tab.
private struct WorkspaceRowView: View {
    let model: AppModel
    let task: TodayItem
    let projectID: Int64
    let link: HerdrLink
    let launchPosition: Int?

    private var isMissing: Bool {
        guard let herdr = model.herdr else { return false }
        return HerdrLinkState(link, herdr) == .notFound
    }

    private var workspaceDetail: String {
        isMissing ? "Not found in Herdr"
            : "Herdr workspace · All tasks in \(task.projectTitle ?? "the project")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "rectangle.split.3x1")
                    .foregroundStyle(isMissing ? Color.orange : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: link.label)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(workspaceDetail)
                        .font(.caption)
                        .foregroundStyle(isMissing ? Color.orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(link.label + ", " + workspaceDetail.replacing(" · ", with: ", "))
                Spacer(minLength: 0)
            }
            HStack {
                Toggle("Opens with context", isOn: Binding(
                    get: { launchPosition != nil },
                    set: { included in Task { await model.setLaunch(.workspace(projectID), included: included) } }))
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("\(link.label) workspace opens with context")
                if let launchPosition {
                    Text("· \(launchPosition + 1)")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("opens \(ordinal(launchPosition + 1))")
                }
                Spacer()
                if launchPosition ?? 0 > 0 {
                    Button("Open Earlier") { Task { await model.moveEarlier(.workspace(projectID), forTask: task.id) } }
                        .buttonStyle(.link)
                }
            }
            .font(.caption)
            .controlSize(.small)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
        .contrastBorder(cornerRadius: 8)
    }
}

/// "Resources", "Agent": the inspector's section headings.
struct SectionTitle: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

/// Links a folder, web page or Herdr agent to a task or its project
/// (design 14). Folders come from an open panel, so FocusPilot only ever
/// reads folders the owner chose.
struct LinkResourceSheet: View {
    enum Kind: Hashable {
        case folder, webPage, agent
    }

    let model: AppModel
    let task: TodayItem
    @Environment(\.dismiss) private var dismiss
    @State private var kind = Kind.folder
    @State private var folder: URL?
    @State private var address = ""
    @State private var forProject = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: "Link a resource to “\(task.title)”")
                    .font(.headline)
                Picker("Kind", selection: $kind) {
                    Text("Folder").tag(Kind.folder)
                    Text("Web page").tag(Kind.webPage)
                    Text("Herdr agent").tag(Kind.agent)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, kind == .agent ? 0 : 12)
            if kind == .agent {
                AgentLinkSheet(model: model, task: task)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if kind == .folder { folderForm } else { pageForm }
                    if let projectTitle = task.projectTitle {
                        Picker("Link to", selection: $forProject) {
                            Text("This task").tag(false)
                            Text(verbatim: "All tasks in \(projectTitle)").tag(true)
                        }
                        .pickerStyle(.radioGroup)
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 20)
                .frame(minHeight: 180, alignment: .top)
                Divider()
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button(kind == .folder ? "Link Folder" : "Link Page") { link() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(kind == .folder ? folder == nil : page == nil)
                }
                .padding(20)
            }
        }
        .frame(width: 560)
        .onChange(of: kind) { error = nil }
    }

    private var folderForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Choose Folder…") {
                    if let url = AppModel.chooseFolder(prompt: "Choose") { folder = url }
                }
                if let folder {
                    Text(verbatim: ResourceText.path(folder.path))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var page: WebPageLink? { try? WebPageLink(address) }

    private var pageForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Address", text: $address, prompt: Text(verbatim: "overleaf.com/project/nlp-report"))
                .textFieldStyle(.roundedBorder)
                .onSubmit { if page != nil { link() } }
            if let page {
                Text(verbatim: page.url)
                    .font(.callout)
                Text(ResourceText.sessionNote(for: page, rules: model.ruleSets))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if !address.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(WebPageLinkError.invalid.message)
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var owner: ResourceOwner {
        if forProject, let projectID = task.projectID { .project(projectID) } else { .task(task.id) }
    }

    private func link() {
        Task {
            switch kind {
            case .folder:
                guard let folder else { return }
                if await model.linkFolder(folder, to: owner) { dismiss() } else { error = model.contextNotice }
            case .webPage:
                error = await model.linkWebPage(address, to: owner)
                if error == nil { dismiss() }
            case .agent:
                break
            }
        }
    }
}
