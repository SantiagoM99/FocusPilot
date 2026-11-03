import Foundation

/// What a resource is linked to. A project's resources show, and can open,
/// with every one of its tasks.
public enum ResourceOwner: Hashable, Sendable {
    case task(Int64)
    case project(Int64)
}

/// A folder or web page linked to a task or project (WORKSPACE_RULES:
/// attached, never copied).
public enum ResourceTarget: Equatable, Sendable {
    case folder(FolderBookmark)
    case webPage(WebPageLink)
}

public struct ContextResource: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var owner: ResourceOwner
    public var target: ResourceTarget
    /// Its place in the launch set; nil when Open context leaves it closed.
    public var launchOrder: Int?
    public var createdAt: Date

    /// "nlp-report", "overleaf.com/project/nlp-report".
    public var name: String {
        switch target {
        case .folder(let bookmark): bookmark.name
        case .webPage(let page): page.displayName
        }
    }

    public var folderBookmark: FolderBookmark? {
        if case .folder(let bookmark) = target { bookmark } else { nil }
    }

    public var webPage: WebPageLink? {
        if case .webPage(let page) = target { page } else { nil }
    }
}

/// Something that can be in a task's launch set: a resource, a Herdr agent
/// linked to the task, or the Herdr workspace linked to its project.
public enum ContextItem: Hashable, Sendable {
    case resource(Int64)
    case agent(Int64)
    /// The project's workspace, by project ID; opened at its first tab.
    case workspace(Int64)
}

/// A resource as the task's Resources section shows it.
public struct ResourceStatus: Equatable, Sendable, Identifiable {
    public var resource: ContextResource
    /// Linked to the task's project rather than the task.
    public var isFromProject: Bool
    /// For a folder, what revalidating it found just now.
    public var folder: FolderCheck?

    public var id: Int64 { resource.id }
}

/// Everything linked to a task, and its launch set in order.
public struct TaskContext: Equatable, Sendable {
    /// The task's own resources, then its project's, each oldest first.
    public var resources: [ResourceStatus]
    public var agents: [TaskAgentLink]
    public var launchSet: [ContextItem]
}

/// One thing Open context opens.
public enum LaunchStep: Equatable, Sendable {
    case folder(Int64, FolderBookmark)
    case webPage(Int64, URL)
    /// Focused through Herdr, which revalidates the agent first.
    case agent(Int64)
    /// The project's workspace, checked against Herdr first, then its first tab focused.
    case workspace(Int64)

    public var item: ContextItem {
        switch self {
        case .folder(let id, _), .webPage(let id, _): .resource(id)
        case .agent(let id): .agent(id)
        case .workspace(let id): .workspace(id)
        }
    }
}

/// A launch-set folder that cannot be opened as it is.
public struct BrokenResource: Equatable, Sendable {
    public var resource: ContextResource
    public var problem: FolderProblem
}

/// A launch-set folder that moved; it opens at its new place.
public struct MovedFolder: Equatable, Sendable {
    public var name: String
    public var path: String
}

/// What Open context will do, worked out right before it opens anything.
/// Nothing in it creates a folder, task or workspace.
public struct LaunchPlan: Equatable, Sendable {
    public var steps: [LaunchStep]
    public var needsRepair: [BrokenResource]
    public var moved: [MovedFolder]
}
