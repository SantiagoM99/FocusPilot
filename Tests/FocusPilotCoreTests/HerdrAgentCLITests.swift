import Foundation
import Testing
@testable import FocusPilotCore

@Suite("Herdr CLI agents")
struct HerdrAgentCLITests {
    private let home = URL(fileURLWithPath: "/Users/owner")
    private let serverStart = instant("2026-09-19T21:05:55-05:00")
    private var server: HerdrServer {
        HerdrServer(sessionName: "default", socketPath: "/Users/owner/.config/herdr/herdr.sock", startedAt: serverStart)
    }

    private func runner(output: String = "Ablation table ready.\n", focusStatus: Int32 = 0) -> RecordingRunner {
        let runner = RecordingRunner(listing: workspaceListJSON)
        runner.replies[["agent", "list"]] = .success(HerdrProcessOutput(status: 0, standardOutput: Data(agentListJSON.utf8)))
        runner.replies[["agent", "read", "w4:p2", "--source", "visible"]] =
            .success(HerdrProcessOutput(status: 0, standardOutput: Data(output.utf8)))
        runner.replies[["agent", "focus", "w4:p2"]] =
            .success(HerdrProcessOutput(status: focusStatus, standardOutput: Data("{}".utf8)))
        return runner
    }

    private func cli(_ runner: RecordingRunner, socketStart: Date? = nil) -> HerdrCLI {
        let start = socketStart ?? serverStart
        return HerdrCLI(home: home, runner: runner, isExecutable: { $0.path == "/Users/owner/.local/bin/herdr" },
                        socketCreationDate: { $0.path == "/Users/owner/.config/herdr/herdr.sock" ? start : nil })
    }

    @Test func listsAgentsAfterCheckingTheServer() async {
        let runner = runner()
        let agents = await cli(runner).agents()

        guard case .connected(let reported, let list) = agents else {
            Issue.record("expected agents, got \(agents)")
            return
        }
        #expect(reported == server)
        #expect(list.map(\.paneID) == ["w4:p2", "w4:pA", "w3:pJ"])
        #expect(runner.launches.map(\.arguments) == [["status", "--json"], ["agent", "list"]])
    }

    @Test func listingNeverFocusesOrReads() async {
        let runner = runner()
        for _ in 0..<3 { _ = await cli(runner).agents() }
        #expect(runner.launches.allSatisfy { Set(["read", "focus"]).isDisjoint(with: $0.arguments) })
    }

    @Test func anUnreadableAgentListIsReported() async {
        let runner = runner()
        runner.replies[["agent", "list"]] = .success(HerdrProcessOutput(status: 0, standardOutput: Data("[]".utf8)))
        #expect(await cli(runner).agents() == .disconnected(.unreadableReply))
    }

    @Test func readsOnlyTheVisibleScreenOfThatPane() async {
        let runner = runner()
        #expect(await cli(runner).output(of: "w4:p2", on: server) == "Ablation table ready.\n")
        #expect(runner.launches.last?.arguments == ["agent", "read", "w4:p2", "--source", "visible"])
    }

    @Test func readingTheScreenIsCappedBeforeItIsHeldInMemory() async {
        let runner = runner()
        _ = await cli(runner).output(of: "w4:p2", on: server)
        #expect(runner.launches.last?.outputLimit == HerdrCLI.screenOutputLimit)
        #expect(runner.launches.dropLast().allSatisfy { $0.outputLimit == nil })
    }

    @Test func focusesThePaneOnTheSameServerInstance() async {
        let runner = runner()
        #expect(await cli(runner).focus("w4:p2", on: server))
        #expect(runner.launches.map(\.arguments) == [["status", "--json"], ["agent", "focus", "w4:p2"]])
    }

    @Test func afterAHerdrRestartNothingIsReadOrFocused() async {
        // The same pane ID may now be someone else's agent.
        let runner = runner()
        let restarted = cli(runner, socketStart: serverStart.addingTimeInterval(3600))
        #expect(await restarted.focus("w4:p2", on: server) == false)
        #expect(await restarted.output(of: "w4:p2", on: server) == nil)
        #expect(runner.launches.allSatisfy { !$0.arguments.contains("focus") && !$0.arguments.contains("read") })
    }

    @Test func aPaneIDOfTheWrongShapeIsNeverPassedToHerdr() async {
        let runner = runner()
        #expect(await cli(runner).focus("--help", on: server) == false)
        #expect(await cli(runner).output(of: "w4:p2 x", on: server) == nil)
        #expect(runner.launches.isEmpty)
    }

    @Test func aFailedFocusIsReported() async {
        #expect(await cli(runner(focusStatus: 1)).focus("w4:p2", on: server) == false)
    }

    @Test func agentCommandsGetTheScrubbedEnvironmentToo() async {
        let runner = runner()
        let herdr = cli(runner)
        _ = await herdr.agents()
        _ = await herdr.output(of: "w4:p2", on: server)
        _ = await herdr.focus("w4:p2", on: server)
        #expect(Set(runner.launches.map(\.environment)) == [[
            "HOME": "/Users/owner", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8",
        ]])
    }
}

@Suite("Agent output preview")
struct AgentOutputPreviewTests {
    @Test func keepsPlainTextLinesInOrder() {
        let preview = AgentOutputPreview("Ablation table ready: 5 rows.\nSeed 3 underperforms.\n")
        #expect(preview.lines == ["Ablation table ready: 5 rows.", "Seed 3 underperforms."])
        #expect(preview.totalLineCount == 2)
    }

    @Test func terminalEscapesAndControlCharactersAreRemoved() {
        let raw = "\u{1B}[1;31mError\u{1B}[0m in \u{1B}]0;title\u{07}run\u{0}\u{8}\r\nok\u{1B}[2K"
        #expect(AgentOutputPreview(raw).lines == ["Error in run", "ok"])
    }

    @Test func blankLinesAndBoxDrawingRulesAreDropped() {
        let raw = "Done.\n\n────────────\n   \n╭──╮\n│  │\nNext step"
        #expect(AgentOutputPreview(raw).lines == ["Done.", "Next step"])
    }

    @Test func keepsOnlyTheLastLinesWithTheTotalCounted() {
        let raw = (1...100).map { "line \($0)" }.joined(separator: "\n")
        let preview = AgentOutputPreview(raw)
        #expect(preview.lines.count == AgentOutputPreview.maximumLines)
        #expect(preview.lines.last == "line 100")
        #expect(preview.totalLineCount == 100)
    }

    @Test func directionOverridesAndInvisibleFormatCharactersAreRemoved() {
        // U+202E would show "txt.exe" reversed; U+200B and U+2066 are invisible.
        #expect(AgentOutputPreview("open \u{202E}exe.txt\u{202C} now\u{200B}\u{2066}!").lines == ["open exe.txt now!"])
    }

    @Test func longLinesAreCut() {
        let preview = AgentOutputPreview(String(repeating: "x", count: 5000))
        #expect(preview.lines.first?.count == AgentOutputPreview.maximumLineLength)
    }

    @Test func roundTripsThroughItsStoredText() {
        let preview = AgentOutputPreview("one\ntwo\nthree")
        #expect(AgentOutputPreview(storedText: preview.storedText, totalLineCount: 3) == preview)
    }
}
