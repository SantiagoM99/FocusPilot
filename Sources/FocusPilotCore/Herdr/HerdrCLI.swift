import Foundation

/// Reads the workspaces of the local default Herdr session through its CLI,
/// following the recipe validated in spike S4 (#4).
public struct HerdrCLI: Sendable {
    /// A GUI app's PATH does not include where Herdr installs itself, and a
    /// login shell does not reliably add it either, so only fixed paths are
    /// tried, in this order.
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

        let output: HerdrProcessOutput
        do {
            output = try await runner.run(executable: binary, arguments: HerdrCommand.workspaceList.arguments,
                                          environment: environment)
        } catch {
            return .disconnected(.notRunning)
        }
        guard output.status == 0 else { return .disconnected(.notRunning) }
        guard let workspaces = HerdrWorkspaceList.parse(output.standardOutput) else {
            return .disconnected(.unreadableReply)
        }
        return .connected(server, workspaces)
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
