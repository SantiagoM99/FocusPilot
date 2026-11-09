import AppKit
import FocusPilotCore

/// Context links and Open context (#18). Opening happens only here, after
/// the owner clicks Open context, and only for the launch set; it never
/// creates a folder, task or workspace.
extension AppModel {
    func context(forTask taskID: Int64) async -> TaskContext? {
        guard let coordinator else { return nil }
        do {
            return try await coordinator.context(forTask: taskID)
        } catch {
            contextNotice = "Could not read this task’s resources: \(error.localizedDescription)"
            return nil
        }
    }

    /// Links a folder the owner chose in an open panel. False if it could
    /// not be linked; `contextNotice` says why.
    @discardableResult
    func linkFolder(_ url: URL, to owner: ResourceOwner) async -> Bool {
        await performContext("Could not link the folder") { try await $0.linkFolder(url, to: owner) }
    }

    /// Nil when linked, else why not.
    func linkWebPage(_ typed: String, to owner: ResourceOwner) async -> String? {
        guard let coordinator else { return nil }
        do {
            try await coordinator.linkWebPage(typed, to: owner)
            contextRevision += 1
            await refresh()
            return nil
        } catch let error as WebPageLinkError {
            return error.message
        } catch {
            return "Could not link the page: \(error.localizedDescription)"
        }
    }

    func relinkFolder(_ id: Int64, near path: String) async {
        guard let url = Self.chooseFolder(prompt: "Relink", startingNear: path) else { return }
        await performContext("Could not relink the folder") { try await $0.relinkFolder(id, to: url) }
    }

    func useFolderNowAtPath(_ id: Int64) async {
        await performContext("Could not use that folder") { try await $0.useFolderNowAtPath(id) }
    }

    func unlinkResource(_ id: Int64) async {
        await performContext("Could not unlink it") { try await $0.unlinkResource(id) }
    }

    func setLaunch(_ item: ContextItem, included: Bool) async {
        await performContext("Could not change what opens") { try await $0.setLaunch(item, included: included) }
    }

    func moveEarlier(_ item: ContextItem, forTask taskID: Int64) async {
        await performContext("Could not change the order") { try await $0.moveEarlier(item, forTask: taskID) }
    }

    /// The owner clicked Open context: revalidates the launch set, opens the
    /// healthy items in order, and says what needs repair.
    func openContext(forTask taskID: Int64, fromNowCard: Bool = false) async {
        guard let coordinator else { return }
        contextNoticeOnNowCard = fromNowCard
        let plan: LaunchPlan
        do {
            plan = try await coordinator.prepareLaunch(forTask: taskID)
        } catch {
            contextNotice = "Could not open the context: \(error.localizedDescription)"
            return
        }
        let resources = (try? await coordinator.context(forTask: taskID).resources) ?? []
        contextNotice = await LaunchRun.run(plan, names: { step in
            switch step {
            case .folder(_, let bookmark): bookmark.name
            case .webPage(let id, let url): resources.first { $0.id == id }?.resource.name ?? url.absoluteString
            case .agent(let linkID): agentLinks.first { $0.id == linkID }?.label ?? "agent"
            case .workspace(let projectID): projects.first { $0.id == projectID }?.herdrLink?.label ?? "workspace"
            }
        }, open: { step in
            switch step {
            case .folder(_, let bookmark): Self.open(bookmark)
            case .webPage(_, let url): NSWorkspace.shared.open(url)
            case .agent(let linkID): await coordinator.openAgent(linkID) == .opened
            case .workspace(let projectID): await coordinator.openWorkspace(ofProject: projectID) == .opened
            }
        })
        contextRevision += 1
        await refresh()
    }

    /// The owner clicked one resource in the inspector.
    func openResource(_ status: ResourceStatus) {
        let opened = switch status.resource.target {
        case .folder(let bookmark): Self.open(bookmark)
        case .webPage(let page): URL(string: page.url).map { NSWorkspace.shared.open($0) } ?? false
        }
        contextNoticeOnNowCard = false
        contextNotice = opened ? nil : "“\(status.resource.name)” didn’t open."
    }

    static func chooseFolder(prompt: String, startingNear path: String? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = prompt
        if let path {
            panel.directoryURL = URL(fileURLWithPath: (path as NSString).deletingLastPathComponent, isDirectory: true)
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func open(_ bookmark: FolderBookmark) -> Bool {
        guard let url = SystemFolderAccess.url(for: bookmark) else { return false }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return NSWorkspace.shared.open(url)
    }

    @discardableResult
    private func performContext(_ failure: String, _ change: (FocusCoordinator) async throws -> Void) async -> Bool {
        guard let coordinator else { return false }
        do {
            try await change(coordinator)
        } catch FolderLinkError.notAFolder {
            contextNotice = "\(failure): that isn’t a folder."
            return false
        } catch FolderLinkError.outsideRoot {
            contextNotice = "\(failure): it isn’t inside the folder it belongs to."
            return false
        } catch {
            contextNotice = "\(failure): \(error.localizedDescription)"
            return false
        }
        contextNotice = nil
        contextNoticeOnNowCard = false
        contextRevision += 1
        await refresh()
        return true
    }
}
