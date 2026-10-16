import Foundation

/// Reads the workspaces of the local default Herdr session through its CLI,
/// following the recipe validated in spike S4 (#4).
public struct HerdrCLI: Sendable {
    /// A GUI app's PATH does not include where Herdr installs itself, and a
    /// login shell does not reliably add it either, so only fixed paths are
    /// tried, in this order.
    /// The socket protocol this client was validated against (Herdr 0.9.0).
    static let supportedProtocol = 22

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
        guard let binary = binary() else { return .disconnected(.binaryNotFound) }
        // The default session's socket. Checked before running anything,
        // because the CLI might start a server that is not running.
        let socket = home.appending(path: ".config/herdr/herdr.sock")
        guard let startedAt = socketCreationDate(socket) else { return .disconnected(.notRunning) }
        let server = HerdrServer(sessionName: "default", socketPath: socket.path, startedAt: startedAt)

        guard let status = await run(.status, with: binary) else { return .disconnected(.notRunning) }
        switch HerdrStatus.parse(status) {
        case .stopped: return .disconnected(.notRunning)
        case .unsupported: return .disconnected(.unsupportedVersion)
        case .compatible: break
        }
        guard let output = await run(.workspaceList, with: binary) else { return .disconnected(.notRunning) }
        guard let workspaces = HerdrWorkspaceList.parse(output) else {
            return .disconnected(.unreadableReply)
        }
        return .connected(server, workspaces)
    }

    /// The command's output, or nil if it could not run or failed.
    private func run(_ command: HerdrCommand, with binary: URL) async -> Data? {
        guard let output = try? await runner.run(executable: binary, arguments: command.arguments, environment: environment),
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
