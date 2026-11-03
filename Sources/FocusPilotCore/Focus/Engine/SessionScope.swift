import Foundation

/// What a focus session covers (#56, decision 0004): every project, or the
/// projects the owner chose at the start. Titles are kept as they were then,
/// so the session can be named without reading the projects again.
public struct SessionScope: Codable, Hashable, Sendable {
    /// Empty for all projects.
    public var projects: [ScopedProject]
    /// Projects outside `projects` whose task the owner pinned as Now during
    /// the session (owner default, review of #60): their resources are
    /// allowed too. Blocking does not change.
    public var alsoAllowed: [ScopedProject]

    public init(projects: [ScopedProject], alsoAllowed: [ScopedProject] = []) {
        self.projects = projects
        self.alsoAllowed = alsoAllowed
    }

    public static let allProjects = SessionScope(projects: [])

    public var isAllProjects: Bool { projects.isEmpty }

    /// Whether a task in `projectID` (nil for no project) is one the session covers.
    public func covers(projectID: Int64?) -> Bool {
        isAllProjects || projects.contains { $0.id == projectID }
    }

    /// Allows a pinned task's project when the session does not cover it.
    public mutating func allow(_ project: ScopedProject) {
        guard !covers(projectID: project.id), !alsoAllowed.contains(project) else { return }
        alsoAllowed.append(project)
    }

    enum CodingKeys: String, CodingKey {
        case projects, alsoAllowed
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(projects: try container.decode([ScopedProject].self, forKey: .projects),
                  alsoAllowed: try container.decodeIfPresent([ScopedProject].self, forKey: .alsoAllowed) ?? [])
    }
}

public struct ScopedProject: Codable, Hashable, Sendable {
    public var id: Int64
    public var title: String

    public init(id: Int64, title: String) {
        self.id = id
        self.title = title
    }
}
