import Foundation

/// Reads the workspaces of the local default Herdr session through its CLI,
/// following the recipe validated in spike S4 (#4).
public struct HerdrCLI: Sendable {
    /// A GUI app's PATH does not include where Herdr installs itself, and a
    /// login shell does not reliably add it either, so only fixed paths are
    /// tried, in this order.
    /// The socket protocol this client was validated against (Herdr 0.9.0).
    static let supportedProtocol = 22

    /// A pane's visible screen is a few kilobytes; more is not a screen.
    static let screenOutputLimit = 64 * 1024

    static let binaryCandidates = [".local/bin/herdr", "/opt/homebrew/bin/herdr", "/usr/local/bin/herdr", ".cargo/bin/herdr"]

    private let home: URL
    private let runner: any HerdrProcessRunning
    private let isExecutable: @Sendable (URL) -> Bool
    private let socketCreationDate: @Sendable (URL) -> Date?

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                runner: any HerdrProcessRunning = HerdrProcessRunner(),
                isExecutable: @escaping @Sendable (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) },
                socketCreationDate: @escaping @Sendable (URL) -> Date? = {
                    try? FileManager.default.attributesOfItem(atPath: $0.path)[.creationDate] as? Date
                }) {
        self.home = home
        self.runner = runner
        self.isExecutable = isExecutable
        self.socketCreationDate = socketCreationDate
    }

    public func connection() async -> HerdrConnection {
        let binary: URL, server: HerdrServer
        switch await reach() {
        case .failure(let reason): return .disconnected(reason)
        case .success(let reached): (binary, server) = reached
        }
        guard let output = await run(.workspaceList, with: binary) else { return .disconnected(.notRunning) }
        guard let workspaces = HerdrWorkspaceList.parse(output) else {
            return .disconnected(.unreadableReply)
        }
        return .connected(server, workspaces)
    }

    public func agents() async -> HerdrAgents {
        let binary: URL, server: HerdrServer
        switch await reach() {
        case .failure(let reason): return .disconnected(reason)
        case .success(let reached): (binary, server) = reached
        }
        guard let output = await run(.agentList, with: binary) else { return .disconnected(.notRunning) }
        guard let agents = HerdrAgentList.parse(output) else { return .disconnected(.unreadableReply) }
        return .connected(server, agents)
    }

    /// The pane's visible screen as text, if `server` is still the running
    /// instance. The text is untrusted and is only ever displayed.
    public func output(of paneID: String, on server: HerdrServer) async -> String? {
        guard let binary = await binary(reaching: server, for: paneID),
              let data = await run(.agentRead(paneID: paneID), with: binary)
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Runs `agent focus` on the pane, if `server` is still the running
    /// instance. Only Open agent calls this, after the owner's click.
    public func focus(_ paneID: String, on server: HerdrServer) async -> Bool {
        guard let binary = await binary(reaching: server, for: paneID) else { return false }
        return await run(.agentFocus(paneID: paneID), with: binary) != nil
    }

    /// The binary, once the pane ID has Herdr's shape and the running server
    /// is the same instance that reported it: after a restart the same pane
    /// ID can name another agent.
    private func binary(reaching expected: HerdrServer, for paneID: String) async -> URL? {
        guard HerdrPaneID.isValid(paneID), case .success(let (binary, server)) = await reach(), server == expected
        else { return nil }
        return binary
    }

    /// The binary and the running default-session server, once its status
    /// says it is compatible.
    private func reach() async -> Result<(URL, HerdrServer), HerdrUnavailable> {
        guard let binary = binary() else { return .failure(.binaryNotFound) }
        // The default session's socket. Checked before running anything,
        // because the CLI might start a server that is not running.
        let socket = home.appending(path: ".config/herdr/herdr.sock")
        guard let startedAt = socketCreationDate(socket) else { return .failure(.notRunning) }
        let server = HerdrServer(sessionName: "default", socketPath: socket.path, startedAt: startedAt)

        guard let status = await run(.status, with: binary) else { return .failure(.notRunning) }
        switch HerdrStatus.parse(status) {
        case .stopped: return .failure(.notRunning)
        case .unsupported: return .failure(.unsupportedVersion)
        case .compatible: return .success((binary, server))
        }
    }

    /// The command's output, or nil if it could not run or failed.
    private func run(_ command: HerdrCommand, with binary: URL) async -> Data? {
        let limit = if case .agentRead = command { Self.screenOutputLimit } else { nil as Int? }
        guard let output = try? await runner.run(executable: binary, arguments: command.arguments, environment: environment,
                                                 outputLimit: limit),
              output.status == 0
        else { return nil }
        return output.standardOutput
    }

    private func binary() -> URL? {
        Self.binaryCandidates
            .map { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : home.appending(path: $0) }
            .first(where: isExecutable)
    }

    /// A terminal-launched app inherits the terminal's environment, and a
    /// leaked HERDR_SOCKET_PATH would silently point the CLI at another
    /// session, so the child gets only these variables.
    private var environment: [String: String] {
        ["HOME": home.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8"]
    }
}

/// Reads `herdr status --json`. Anything other than a running, compatible
/// server on the supported protocol is unsupported, including output that
/// cannot be read.
enum HerdrStatus {
    case compatible, stopped, unsupported

    static func parse(_ data: Data) -> HerdrStatus {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let server = root["server"] as? [String: Any],
              let running = server["running"] as? Bool
        else { return .unsupported }
        guard running else { return .stopped }
        guard server["compatible"] as? Bool == true, server["protocol"] as? Int == HerdrCLI.supportedProtocol
        else { return .unsupported }
        return .compatible
    }
}

/// Parses `herdr workspace list` output. The reply is untrusted: any field
/// of the wrong type rejects the whole reply rather than guessing.
enum HerdrWorkspaceList {
    static func parse(_ data: Data) -> [HerdrWorkspace]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let items = result["workspaces"] as? [[String: Any]]
        else { return nil }
        var workspaces: [HerdrWorkspace] = []
        for item in items {
            guard let id = item["workspace_id"] as? String, let label = item["label"] as? String else { return nil }
            let worktree = item["worktree"] as? [String: Any]
            workspaces.append(HerdrWorkspace(id: id, label: label, cwd: worktree?["checkout_path"] as? String,
                                             isLinkedWorktree: worktree?["is_linked_worktree"] as? Bool ?? false))
        }
        return workspaces
    }
}

/// Where the coordinator reads Herdr's workspaces from.
public protocol HerdrWorkspaceSource: Sendable {
    func connection() async -> HerdrConnection
}

extension HerdrCLI: HerdrWorkspaceSource {}

/// Where the coordinator reads agents from, and the one way it changes what
/// the owner sees in Herdr.
public protocol HerdrAgentSource: Sendable {
    func agents() async -> HerdrAgents
    func output(of paneID: String, on server: HerdrServer) async -> String?
    func focus(_ paneID: String, on server: HerdrServer) async -> Bool
}

extension HerdrCLI: HerdrAgentSource {}
