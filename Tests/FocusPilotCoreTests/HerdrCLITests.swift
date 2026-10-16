import Foundation
import Testing
@testable import FocusPilotCore

/// Stands in for the herdr binary: records every launch and answers with a
/// canned reply.
final class RecordingRunner: HerdrProcessRunning, @unchecked Sendable {
    struct Launch: Equatable {
        var executable: String
        var arguments: [String]
        var environment: [String: String]
    }

    private let lock = NSLock()
    private var recorded: [Launch] = []
    var reply: Result<HerdrProcessOutput, Error>

    init(reply: Result<HerdrProcessOutput, Error>) {
        self.reply = reply
    }

    var launches: [Launch] { lock.withLock { recorded } }

    func run(executable: URL, arguments: [String], environment: [String: String]) async throws -> HerdrProcessOutput {
        lock.withLock { recorded.append(Launch(executable: executable.path, arguments: arguments, environment: environment)) }
        return try reply.get()
    }
}

/// The shape `herdr workspace list` printed on this Mac (Herdr 0.9.0): the
/// `worktree` object is present only for workspaces opened on a Git checkout.
let workspaceListJSON = """
    {"id":"cli:workspace:list","result":{"type":"workspace_list","workspaces":[
      {"active_tab_id":"w3:tJ","agent_status":"idle","focused":false,"label":"M2-Align","number":1,
       "pane_count":3,"tab_count":3,"workspace_id":"w3"},
      {"active_tab_id":"w4:t1","agent_status":"idle","focused":false,"label":"AlignFreeze","number":2,
       "pane_count":4,"tab_count":4,"workspace_id":"w4",
       "worktree":{"checkout_path":"/Users/owner/Projects/NLP/nlp_project","is_linked_worktree":false,
                   "repo_key":"/Users/owner/Projects/NLP/nlp_project/.git","repo_name":"nlp_project",
                   "repo_root":"/Users/owner/Projects/NLP/nlp_project"}},
      {"active_tab_id":"wP:t1","agent_status":"working","focused":false,"label":"nlp_project · fix-seeds","number":3,
       "pane_count":1,"tab_count":1,"workspace_id":"wP",
       "worktree":{"checkout_path":"/Users/owner/Projects/NLP/nlp_project/.worktrees/fix-seeds","is_linked_worktree":true,
                   "repo_key":"/Users/owner/Projects/NLP/nlp_project/.git","repo_name":"nlp_project",
                   "repo_root":"/Users/owner/Projects/NLP/nlp_project"}}
    ]}}
    """

@Suite("Herdr CLI")
struct HerdrCLITests {
    private let home = URL(fileURLWithPath: "/Users/owner")
    private let serverStart = instant("2026-09-19T21:05:55-05:00")

    private func cli(runner: RecordingRunner, executables: Set<String> = ["/Users/owner/.local/bin/herdr"],
                     socketStart: Date?? = nil) -> HerdrCLI {
        let start = socketStart ?? serverStart
        return HerdrCLI(home: home, runner: runner,
                        isExecutable: { executables.contains($0.path) },
                        socketCreationDate: { $0.path == "/Users/owner/.config/herdr/herdr.sock" ? start : nil })
    }

    private func listing(_ json: String = workspaceListJSON) -> RecordingRunner {
        RecordingRunner(reply: .success(HerdrProcessOutput(status: 0, standardOutput: Data(json.utf8))))
    }

    @Test func readsWorkspacesWithTheirLabelAndCheckout() async {
        let connection = await cli(runner: listing()).connection()

        guard case .connected(let server, let workspaces) = connection else {
            Issue.record("expected a connection, got \(connection)")
            return
        }
        #expect(server == HerdrServer(sessionName: "default", socketPath: "/Users/owner/.config/herdr/herdr.sock",
                                      startedAt: serverStart))
        #expect(workspaces == [
            HerdrWorkspace(id: "w3", label: "M2-Align", cwd: nil, isLinkedWorktree: false),
            HerdrWorkspace(id: "w4", label: "AlignFreeze", cwd: "/Users/owner/Projects/NLP/nlp_project", isLinkedWorktree: false),
            HerdrWorkspace(id: "wP", label: "nlp_project · fix-seeds",
                           cwd: "/Users/owner/Projects/NLP/nlp_project/.worktrees/fix-seeds", isLinkedWorktree: true),
        ])
    }

    @Test func onlyReadOnlyWorkspaceCommandsAreEverRun() async {
        let runner = listing()
        let herdr = cli(runner: runner)
        _ = await herdr.connection()
        _ = await herdr.connection()

        #expect(!runner.launches.isEmpty)
        for launch in runner.launches {
            #expect([["workspace", "list"], ["workspace", "get"]].contains(Array(launch.arguments.prefix(2))))
        }
        for command in HerdrCommand.allCases {
            #expect(["list", "get"].contains(command.arguments[1]), "\(command) is not read-only")
        }
    }

    @Test func childGetsAScrubbedEnvironmentWithoutHerdrVariables() async {
        let runner = listing()
        _ = await cli(runner: runner).connection()

        #expect(runner.launches.first?.environment == [
            "HOME": "/Users/owner", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8",
        ])
    }

    @Test func findsTheBinaryAtAFixedPathNotThroughPATH() async {
        let runner = listing()
        _ = await cli(runner: runner, executables: ["/opt/homebrew/bin/herdr"]).connection()

        #expect(runner.launches.map(\.executable) == ["/opt/homebrew/bin/herdr"])
    }

    @Test func missingBinaryIsReportedWithoutRunningAnything() async {
        let runner = listing()
        #expect(await cli(runner: runner, executables: []).connection() == .disconnected(.binaryNotFound))
        #expect(runner.launches.isEmpty)
    }

    @Test func noSocketMeansNotRunningAndHerdrIsNotLaunched() async {
        // Running the CLI with no server might start one; FocusPilot must not.
        let runner = listing()
        #expect(await cli(runner: runner, socketStart: .some(nil)).connection() == .disconnected(.notRunning))
        #expect(runner.launches.isEmpty)
    }

    @Test func failedListMeansNotRunning() async {
        let runner = RecordingRunner(reply: .success(HerdrProcessOutput(status: 1, standardOutput: Data())))
        #expect(await cli(runner: runner).connection() == .disconnected(.notRunning))
    }

    @Test func launchFailureMeansNotRunning() async {
        let runner = RecordingRunner(reply: .failure(CocoaError(.executableLoad)))
        #expect(await cli(runner: runner).connection() == .disconnected(.notRunning))
    }

    @Test(arguments: [
        "not json",
        #"{"result":{"workspaces":[{"label":"No id"}]}}"#,
        #"{"result":{"workspaces":[{"workspace_id":7,"label":"Wrong type"}]}}"#,
        #"{"error":{"code":"internal"}}"#,
    ])
    func unexpectedOutputIsReportedAsUnreadable(json: String) async {
        #expect(await cli(runner: listing(json)).connection() == .disconnected(.unreadableReply))
    }
}
