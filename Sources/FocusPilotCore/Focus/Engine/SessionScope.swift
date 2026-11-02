import Foundation

/// What a focus session covers (#56, decision 0004): every project, or the
/// projects the owner chose at the start. Titles are kept as they were then,
/// so the session can be named without reading the projects again.
public struct SessionScope: Codable, Hashable, Sendable {
    /// Empty for all projects.
    public var projects: [ScopedProject]

    public init(projects: [ScopedProject]) {
        self.projects = projects
    }

    public static let allProjects = SessionScope(projects: [])

    public var isAllProjects: Bool { projects.isEmpty }
}

public struct ScopedProject: Codable, Hashable, Sendable {
    public var id: Int64
    public var title: String

    public init(id: Int64, title: String) {
        self.id = id
        self.title = title
    }
}
