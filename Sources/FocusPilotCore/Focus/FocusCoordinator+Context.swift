import Foundation

/// Context links and the launch set (#18, WORKSPACE_RULES). Folders are
/// revalidated whenever they are shown and right before a launch: a moved
/// folder is followed and its new path saved; anything else wrong is
/// reported as needing repair, never silently skipped or substituted.
/// Preparing a launch opens nothing and creates nothing; the owner's Open
/// context click opens the plan.
extension FocusCoordinator {
    @discardableResult
    public func linkFolder(_ url: URL, to owner: ResourceOwner, root: String? = nil) async throws -> ContextResource {
        try await add(.folder(folders.bookmark(url, root: root)), to: owner)
    }

    @discardableResult
    public func linkWebPage(_ typed: String, to owner: ResourceOwner) async throws -> ContextResource {
        try await add(.webPage(WebPageLink(typed)), to: owner)
    }

    public func unlinkResource(_ id: Int64) async throws {
        await publish(try await repository.removeResource(id))
    }

    /// Points a folder link at the folder the owner chose again.
    public func relinkFolder(_ id: Int64, to url: URL) async throws {
        guard let old = try await repository.resource(id)?.folderBookmark else { return }
        try await repository.updateFolder(id, to: folders.bookmark(url, root: old.root))
    }

    /// The owner confirmed that the folder now at the link's path, after it
    /// was deleted and recreated, is the one they mean.
    public func useFolderNowAtPath(_ id: Int64) async throws {
        guard let old = try await repository.resource(id)?.folderBookmark,
              case .needsRepair(.replaced(let path)) = folders.check(old) else { return }
        try await repository.updateFolder(id, to: folders.bookmark(URL(fileURLWithPath: path, isDirectory: true), root: old.root))
    }

    public func context(forTask taskID: Int64) async throws -> TaskContext {
        var statuses: [ResourceStatus] = []
        for resource in try await repository.resources(forTask: taskID) {
            let (current, check) = try await revalidated(resource)
            statuses.append(ResourceStatus(resource: current, isFromProject: resource.owner != .task(taskID), folder: check))
        }
        return TaskContext(resources: statuses, agents: try await repository.agentLinks(forTask: taskID),
                           launchSet: try await repository.launchSet(forTask: taskID))
    }

    public func setLaunch(_ item: ContextItem, included: Bool) async throws {
        try await repository.setLaunch(item, included: included)
    }

    public func moveEarlier(_ item: ContextItem, forTask taskID: Int64) async throws {
        try await repository.moveEarlier(item, forTask: taskID)
    }

    /// Revalidates the launch set and says what Open context opens, in order.
    public func prepareLaunch(forTask taskID: Int64) async throws -> LaunchPlan {
        let resources = Dictionary(uniqueKeysWithValues: try await repository.resources(forTask: taskID).map { ($0.id, $0) })
        var plan = LaunchPlan(steps: [], needsRepair: [], moved: [])
        for item in try await repository.launchSet(forTask: taskID) {
            switch item {
            case .agent(let id):
                plan.steps.append(.agent(id))
            case .workspace(let id):
                plan.steps.append(.workspace(id))
            case .resource(let id):
                guard let resource = resources[id] else { continue }
                let (current, check) = try await revalidated(resource)
                switch (current.target, check) {
                case (.webPage(let page), _):
                    if let url = URL(string: page.url) { plan.steps.append(.webPage(id, url)) }
                case (.folder, .needsRepair(let problem)?):
                    plan.needsRepair.append(BrokenResource(resource: current, problem: problem))
                case (.folder(let bookmark), .moved(let path, _)?):
                    plan.moved.append(MovedFolder(name: resource.name, path: path))
                    plan.steps.append(.folder(id, bookmark))
                case (.folder(let bookmark), _):
                    plan.steps.append(.folder(id, bookmark))
                }
            }
        }
        return plan
    }

    /// The owner clicked Open context: checks the project's workspace is
    /// still the one linked, then focuses its first tab.
    public func openWorkspace(ofProject projectID: Int64) async -> OpenWorkspaceResult {
        guard let herdr, let link = try? await repository.projects().first(where: { $0.id == projectID })?.herdrLink else {
            return .notFound
        }
        let connection = await herdr.connection()
        switch HerdrLinkState(link, connection) {
        case .live:
            return await herdr.focusFirstTab(ofWorkspace: link.workspaceID, on: link.server) ? .opened : .herdrUnavailable
        case .notFound: return .notFound
        case .unknown: return .herdrUnavailable
        }
    }

    private func add(_ target: ResourceTarget, to owner: ResourceOwner) async throws -> ContextResource {
        let (resource, change) = try await repository.addResource(target, to: owner)
        await publish(change)
        return resource
    }

    /// A folder checked now, with a followed move saved.
    private func revalidated(_ resource: ContextResource) async throws -> (ContextResource, FolderCheck?) {
        guard let bookmark = resource.folderBookmark else { return (resource, nil) }
        let check = folders.check(bookmark)
        guard case .moved(_, let refreshed) = check else { return (resource, check) }
        try await repository.updateFolder(resource.id, to: refreshed)
        var current = resource
        current.target = .folder(refreshed)
        return (current, check)
    }
}

/// What opening a project's workspace did.
public enum OpenWorkspaceResult: Equatable, Sendable {
    case opened
    /// Gone from Herdr, or Herdr restarted and its IDs were reissued.
    case notFound
    case herdrUnavailable
}
