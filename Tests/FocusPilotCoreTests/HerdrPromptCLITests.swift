import Foundation
import Testing
@testable import FocusPilotCore

/// Accept on a report sends its text with `herdr agent prompt` (#67): only
/// to a pane of the same server instance, with the text as one argument.
@Suite("Herdr CLI agent prompt")
struct HerdrPromptCLITests {
    private let home = URL(fileURLWithPath: "/Users/owner")
    private let serverStart = instant("2026-09-19T21:05:55-05:00")
    private var server: HerdrServer {
        HerdrServer(sessionName: "default", socketPath: "/Users/owner/.config/herdr/herdr.sock", startedAt: serverStart)
    }
    private let text = "Tests pass. Please open the PR.\nUse the title “Fix seeds”."

    private func runner(status: Int32 = 0, reply: String = #"{"id":"cli:agent:prompt","result":{}}"#) -> RecordingRunner {
        let runner = RecordingRunner(listing: workspaceListJSON)
        runner.replies[["agent", "prompt", "w4:p2", text]] = .success(HerdrProcessOutput(status: status, standardOutput: Data(reply.utf8)))
        return runner
    }

    private func cli(_ runner: RecordingRunner, socketStart: Date? = nil) -> HerdrCLI {
        let start = socketStart ?? serverStart
        return HerdrCLI(home: home, runner: runner, isExecutable: { $0.path == "/Users/owner/.local/bin/herdr" },
                        socketCreationDate: { $0.path == "/Users/owner/.config/herdr/herdr.sock" ? start : nil })
    }

    @Test func sendsTheTextAsOneArgumentAfterCheckingTheServer() async {
        let runner = runner()

        #expect(await cli(runner).prompt("w4:p2", text: text, on: server) == .sent)
        #expect(runner.launches.map(\.arguments) == [["status", "--json"], ["agent", "prompt", "w4:p2", text]])
    }

    @Test func anotherServerInstanceGetsNothing() async {
        let runner = runner()

        #expect(await cli(runner, socketStart: serverStart.addingTimeInterval(60)).prompt("w4:p2", text: text, on: server)
            == .notFound)
        #expect(runner.launches.allSatisfy { !$0.arguments.contains("prompt") })
    }

    @Test(arguments: ["--help", "ablation", "w4:p2 w4:p3", ""])
    func onlyAPaneIDIsATarget(_ pane: String) async {
        let runner = runner()

        #expect(await cli(runner).prompt(pane, text: text, on: server) == .notFound)
        #expect(runner.launches.isEmpty)
    }

    // Herdr 0.9.0 reads a text starting with "--" as an option and has no
    // "--" separator, so such text is never passed.
    @Test(arguments: ["--wait", "-x", "", "a\u{1B}[2J", "ok\u{3}"])
    func textHerdrCouldMisreadIsNeverSent(_ bad: String) async {
        let runner = runner()

        #expect(await cli(runner).prompt("w4:p2", text: bad, on: server) == .refused)
        #expect(runner.launches.isEmpty)
    }

    @Test(arguments: [
        (#"{"error":{"code":"agent_blocked","message":"agent is blocked"},"id":"cli:agent:prompt"}"#, PromptResult.blocked),
        (#"{"error":{"code":"agent_not_found","message":"not found"},"id":"cli:agent:prompt"}"#, .notFound),
        (#"{"error":{"code":"something_else"}}"#, .unknown),
        ("not json", .unknown),
    ])
    func herdrsRefusalsAreReported(reply: String, result: PromptResult) async {
        #expect(await cli(runner(status: 1, reply: reply)).prompt("w4:p2", text: text, on: server) == result)
    }

    // #68 review: once Herdr has started, a timeout or an over-size reply
    // says nothing about whether the agent got the text.
    @Test func aRunThatEndsBadlyIsAnUnknownOutcome() async {
        for error: any Error in [HerdrProcessRunner.TimedOut(), HerdrProcessRunner.OutputTooLarge()] {
            let runner = runner()
            runner.replies[["agent", "prompt", "w4:p2", text]] = .failure(error)

            #expect(await cli(runner).prompt("w4:p2", text: text, on: server) == .unknown)
        }
    }
}
