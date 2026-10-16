/// The Herdr workspace a project is linked to, as it was when linked.
public struct HerdrLink: Equatable, Sendable {
    public var server: HerdrServer
    public var workspaceID: String
    public var label: String
    public var cwd: String?

    public init(server: HerdrServer, workspaceID: String, label: String, cwd: String?) {
        self.server = server
        self.workspaceID = workspaceID
        self.label = label
        self.cwd = cwd
    }
}

public enum HerdrLinkError: Error, Equatable {
    case workspaceAlreadyLinked
}
