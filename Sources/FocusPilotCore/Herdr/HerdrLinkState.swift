/// Whether a project's linked workspace is still open in Herdr.
public enum HerdrLinkState: Equatable, Sendable {
    case live(HerdrWorkspace)
    /// Herdr is reachable but the workspace is not in its list, or the
    /// server restarted and its IDs no longer mean the same workspaces.
    case notFound
    /// Herdr is not reachable, so nothing can be said about the workspace.
    case unknown

    public init(_ link: HerdrLink, _ connection: HerdrConnection) {
        guard case .connected(let server, let workspaces) = connection else {
            self = .unknown
            return
        }
        let workspace = server == link.server ? workspaces.first { $0.id == link.workspaceID } : nil
        self = workspace.map(Self.live) ?? .notFound
    }
}

public enum HerdrRelink {
    /// The workspace a missing link most likely became: same label and same
    /// checkout. The owner confirms before it is applied.
    public static func suggestion(for link: HerdrLink, among workspaces: [HerdrWorkspace]) -> HerdrWorkspace? {
        workspaces.first { $0.label == link.label && $0.cwd == link.cwd }
    }
}

/// One row of the "From Herdr…" picker.
public struct HerdrImportRow: Equatable, Sendable, Identifiable {
    public var workspace: HerdrWorkspace
    public var linkedProjectTitle: String?

    public var id: String { workspace.id }
    public var canImport: Bool { linkedProjectTitle == nil }

    public static func rows(for workspaces: [HerdrWorkspace], on server: HerdrServer,
                            projects: [ProjectSummary]) -> [HerdrImportRow] {
        workspaces.map { workspace in
            let project = projects.first { $0.herdrLink?.server == server && $0.herdrLink?.workspaceID == workspace.id }
            return HerdrImportRow(workspace: workspace, linkedProjectTitle: project?.title)
        }
    }
}
