import Foundation

/// One workspace as `herdr workspace list` reports it. IDs such as "w3" are
/// only meaningful together with the `HerdrServer` that issued them.
public struct HerdrWorkspace: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String
    /// The Git checkout the workspace was opened on. Herdr reports no other
    /// working directory, so workspaces outside a repository have none.
    public var cwd: String?
    /// True for the workspaces Herdr opens on a linked Git worktree, which is
    /// how agents get their own checkout of a repository.
    public var isLinkedWorktree: Bool

    public init(id: String, label: String, cwd: String?, isLinkedWorktree: Bool) {
        self.id = id
        self.label = label
        self.cwd = cwd
        self.isLinkedWorktree = isLinkedWorktree
    }
}

/// The Herdr server instance a workspace ID belongs to.
///
/// Herdr has no server instance ID, and workspace IDs start over when the
/// server restarts, so a stored "w3" may name a different workspace after a
/// restart. The server recreates its socket when it starts, so the socket's
/// creation time tells two instances apart.
public struct HerdrServer: Hashable, Sendable {
    public var sessionName: String
    public var socketPath: String
    /// Rounded to whole milliseconds, the precision it is stored with.
    public private(set) var startedAt: Date

    public init(sessionName: String, socketPath: String, startedAt: Date) {
        self.sessionName = sessionName
        self.socketPath = socketPath
        self.startedAt = Date(timeIntervalSince1970: Double(Self.milliseconds(startedAt)) / 1000)
    }

    var startedAtMilliseconds: Int64 { Self.milliseconds(startedAt) }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}

/// What FocusPilot can currently see of Herdr.
public enum HerdrConnection: Equatable, Sendable {
    case connected(HerdrServer, [HerdrWorkspace])
    case disconnected(HerdrUnavailable)
}

public enum HerdrUnavailable: Equatable, Sendable {
    /// No herdr executable at any of the known install paths.
    case binaryNotFound
    /// No server socket, or the CLI could not reach the server.
    case notRunning
    /// The server speaks a protocol FocusPilot was not built for, or does
    /// not say which.
    case unsupportedVersion
    /// Herdr answered with something FocusPilot does not understand, such as
    /// a newer output format.
    case unreadableReply
}
