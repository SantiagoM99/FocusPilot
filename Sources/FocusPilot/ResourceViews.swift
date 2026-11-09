import FocusPilotCore
import SwiftUI

/// "NOW", "NEXT", "RESOURCES": the redesign's small section headings.
struct SectionTitle: View {
    let title: String
    var color = Color.palette(.secondaryText)

    init(_ title: String, color: Color = .palette(.secondaryText)) {
        self.title = title
        self.color = color
    }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.88)
            .foregroundStyle(color)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isHeader)
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
