import Foundation
import Testing
@testable import FocusPilotCore

/// Opening a project's workspace focuses its first tab: S4 proved
/// `tab focus` from a GUI app (#18).
@Suite("Herdr CLI workspace focus")
struct HerdrTabFocusCLITests {
    private let home = URL(fileURLWithPath: "/Users/owner")
    private let serverStart = instant("2026-09-19T21:05:55-05:00")
    private var server: HerdrServer {
        HerdrServer(sessionName: "default", socketPath: "/Users/owner/.config/herdr/herdr.sock", startedAt: serverStart)
    }

    private func runner(tabs: String) -> RecordingRunner {
        let runner = RecordingRunner(listing: workspaceListJSON)
        runner.replies[["tab", "list", "--workspace", "w4"]] = .success(HerdrProcessOutput(status: 0, standardOutput: Data(tabs.utf8)))
        runner.replies[["tab", "focus", "w4:t3"]] = .success(HerdrProcessOutput(status: 0, standardOutput: Data("{}".utf8)))
        return runner
    }

    private func cli(_ runner: RecordingRunner, socketStart: Date? = nil) -> HerdrCLI {
        let start = socketStart ?? serverStart
        return HerdrCLI(home: home, runner: runner, isExecutable: { $0.path == "/Users/owner/.local/bin/herdr" },
                        socketCreationDate: { $0.path == "/Users/owner/.config/herdr/herdr.sock" ? start : nil })
    }

    private static func tabs(_ ids: [(String, String)]) -> String {
        let items = ids.map { #"{"agent_status":"idle","focused":false,"label":"Claude","number":1,"pane_count":1,"tab_id":"\#($0.0)","workspace_id":"\#($0.1)"}"# }
        return #"{"id":"cli:tab:list","result":{"tabs":[\#(items.joined(separator: ","))],"type":"tab_list"}}"#
    }

    @Test func focusesTheFirstTabHerdrLists() async {
        let runner = runner(tabs: Self.tabs([("w4:t3", "w4"), ("w4:t1", "w4")]))

        #expect(await cli(runner).focusFirstTab(ofWorkspace: "w4", on: server))
        #expect(runner.launches.map(\.arguments) == [["status", "--json"], ["tab", "list", "--workspace", "w4"], ["tab", "focus", "w4:t3"]])
    }

    @Test func anotherServerInstanceIsNotTouched() async {
        let runner = runner(tabs: Self.tabs([("w4:t3", "w4")]))
        let restarted = cli(runner, socketStart: serverStart.addingTimeInterval(60))

        #expect(await restarted.focusFirstTab(ofWorkspace: "w4", on: server) == false)
        #expect(runner.launches.allSatisfy { $0.arguments.first != "tab" })
    }

    @Test(arguments: ["--help", "w4 w5", "", "t1"])
    func onlyHerdrsWorkspaceIDsArePassed(_ id: String) async {
        let runner = runner(tabs: Self.tabs([("w4:t3", "w4")]))

        #expect(await cli(runner).focusFirstTab(ofWorkspace: id, on: server) == false)
        #expect(runner.launches.allSatisfy { $0.arguments.first != "tab" })
    }

    @Test(arguments: [
        tabs([]),
        tabs([("w5:t1", "w5")]),
        tabs([("--help", "w4")]),
        #"{"result":{"tabs":"none"}}"#,
    ])
    func anEmptyOrOddTabListFocusesNothing(_ reply: String) async {
        let runner = runner(tabs: reply)

        #expect(await cli(runner).focusFirstTab(ofWorkspace: "w4", on: server) == false)
        #expect(runner.launches.allSatisfy { $0.arguments.prefix(2) != ["tab", "focus"] })
    }
}
