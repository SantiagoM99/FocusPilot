import Foundation
import Testing
@testable import FocusPilotCore

/// The shape `herdr agent list` printed on this Mac (Herdr 0.9.0), trimmed:
/// a named Claude agent that is working, an unnamed Codex agent that is done,
/// and a pane Herdr cannot classify.
let agentListJSON = """
    {"id":"cli:agent:list","result":{"agents":[
      {"agent":"claude","agent_session":{"agent":"claude","kind":"id","source":"herdr:claude","value":"1ed5cc9b"},
       "agent_status":"working","cwd":"/Users/owner/Projects/NLP/nlp_project","focused":false,"name":"ablation",
       "pane_id":"w4:p2","revision":30,"state_change_seq":2369,"tab_id":"w4:t2","terminal_id":"term_65cf",
       "terminal_title":"✳ Ablation table","terminal_title_stripped":"Ablation table","workspace_id":"w4"},
      {"agent":"codex","agent_status":"done","cwd":"/Users/owner/Projects/NLP/nlp_project","focused":false,
       "pane_id":"w4:pA","revision":2,"state_change_seq":2374,"tab_id":"w4:t6","terminal_id":"term_65d7",
       "workspace_id":"w4"},
      {"agent":"claude","agent_status":"unknown","focused":false,"pane_id":"w3:pJ","tab_id":"w3:tJ",
       "terminal_title_stripped":"","workspace_id":"w3"}
    ]}}
    """

@Suite("Herdr agents")
struct HerdrAgentTests {
    // MARK: Parsing untrusted output

    @Test func readsEachAgentsPaneNameKindStatusAndTitle() throws {
        let agents = try #require(HerdrAgentList.parse(Data(agentListJSON.utf8)))

        #expect(agents == [
            HerdrAgent(paneID: "w4:p2", workspaceID: "w4", tabID: "w4:t2", name: "ablation", kind: "claude",
                       status: .working, title: "Ablation table"),
            HerdrAgent(paneID: "w4:pA", workspaceID: "w4", tabID: "w4:t6", name: nil, kind: "codex",
                       status: .done, title: nil),
            HerdrAgent(paneID: "w3:pJ", workspaceID: "w3", tabID: "w3:tJ", name: nil, kind: "claude",
                       status: .unknown, title: nil),
        ])
    }

    @Test func aStatusFocusPilotDoesNotKnowIsUnknownNeverReady() throws {
        let json = agentListJSON.replacingOccurrences(of: "\"done\"", with: "\"finished\"")
        let agents = try #require(HerdrAgentList.parse(Data(json.utf8)))
        #expect(agents[1].status == .unknown)
        #expect(agents[1].status.activity == .unknown)
    }

    @Test func aFieldOfTheWrongTypeRejectsTheWholeReply() {
        let json = agentListJSON.replacingOccurrences(of: "\"pane_id\":\"w4:pA\"", with: "\"pane_id\":7")
        #expect(HerdrAgentList.parse(Data(json.utf8)) == nil)
        #expect(HerdrAgentList.parse(Data("not json".utf8)) == nil)
    }

    @Test func aPaneIDThatCouldPassAsAnOptionRejectsTheReply() {
        // Pane IDs end up as arguments of `agent read` and `agent focus`.
        for bad in ["--help", "w4:p2 --x", "", "w4:t2", "../w4:p2"] {
            let json = agentListJSON.replacingOccurrences(of: "\"pane_id\":\"w4:p2\"", with: "\"pane_id\":\"\(bad)\"")
            #expect(HerdrAgentList.parse(Data(json.utf8)) == nil, "\(bad) was accepted")
        }
    }

    @Test func longTitlesAndNamesAreCut() throws {
        let json = agentListJSON
            .replacingOccurrences(of: "\"Ablation table\"", with: "\"\(String(repeating: "t", count: 5000))\"")
            .replacingOccurrences(of: "\"ablation\"", with: "\"\(String(repeating: "n", count: 500))\"")
        let first = try #require(HerdrAgentList.parse(Data(json.utf8))?.first)
        #expect(first.title?.count == HerdrAgentList.maximumTitleLength)
        #expect(first.name?.count == HerdrAgentList.maximumNameLength)
    }

    @Test func titlesLoseDirectionAndInvisibleFormatCharacters() throws {
        let json = agentListJSON.replacingOccurrences(of: "\"Ablation table\"", with: "\"Abla\\u202Etion\\u200B table\"")
        #expect(try #require(HerdrAgentList.parse(Data(json.utf8))?.first).title == "Ablation table")
    }

    @Test func aTitleChangeAloneLeavesTheStatusViewEqual() {
        var renamedTitle = agent(.working)
        renamedTitle.title = "Something else"
        #expect(HerdrAgents.connected(herdrServer, [agent(.working)]).ignoringTitles
            == HerdrAgents.connected(herdrServer, [renamedTitle]).ignoringTitles)
        #expect(HerdrAgents.connected(herdrServer, [agent(.working)]).ignoringTitles
            != HerdrAgents.connected(herdrServer, [agent(.idle)]).ignoringTitles)
    }

    @Test func idleAndDoneAreReadyOnlyWorkingAndBlockedAreBusy() {
        #expect(HerdrAgentStatus.idle.activity == .ready)
        #expect(HerdrAgentStatus.done.activity == .ready)
        #expect(HerdrAgentStatus.working.activity == .working)
        #expect(HerdrAgentStatus.blocked.activity == .blocked)
        #expect(HerdrAgentStatus.unknown.activity == .unknown)
    }

    // MARK: What reaches the Review queue

    @Test func finishingAfterWorkingOrBlockedIsAResult() {
        #expect(AgentTransition.review(from: .working, to: .idle) == .finished)
        #expect(AgentTransition.review(from: .working, to: .done) == .finished)
        #expect(AgentTransition.review(from: .blocked, to: .done) == .finished)
    }

    @Test func becomingBlockedIsAnApprovalItem() {
        #expect(AgentTransition.review(from: .working, to: .blocked) == .approval)
        #expect(AgentTransition.review(from: .idle, to: .blocked) == .approval)
        #expect(AgentTransition.review(from: nil, to: .blocked) == .approval)
        #expect(AgentTransition.review(from: .blocked, to: .blocked) == nil)
    }

    @Test func unknownNeverProducesAResult() {
        for previous in [nil, HerdrAgentStatus.working, .blocked, .idle, .done] {
            #expect(AgentTransition.review(from: previous, to: .unknown) == nil)
        }
    }

    @Test func readyWithoutObservedWorkIsNotAResult() {
        // Linked while already ready, or ready the first time it is seen.
        #expect(AgentTransition.review(from: nil, to: .done) == nil)
        #expect(AgentTransition.review(from: .idle, to: .done) == nil)
        #expect(AgentTransition.review(from: .done, to: .idle) == nil)
    }

    @Test func unknownDoesNotReplaceTheLastKnownStatus() {
        #expect(AgentTransition.lastKnown(previous: .working, current: .unknown) == .working)
        #expect(AgentTransition.lastKnown(previous: .working, current: .idle) == .idle)
        #expect(AgentTransition.lastKnown(previous: nil, current: .unknown) == nil)
    }
}

@Suite("Herdr command allowlist")
struct HerdrCommandAllowlistTests {
    /// The only commands FocusPilot may run, written out by hand. The switch
    /// has no default, so a new `HerdrCommand` case does not compile until it
    /// is added here, where review sees it.
    private func pinned(_ command: HerdrCommand) -> [String] {
        switch command {
        case .status: ["status", "--json"]
        case .workspaceList: ["workspace", "list"]
        case .agentList: ["agent", "list"]
        case .agentRead(let pane): ["agent", "read", pane, "--source", "visible"]
        case .agentFocus(let pane): ["agent", "focus", pane]
        }
    }

    private let everyCommand: [HerdrCommand] = [
        .status, .workspaceList, .agentList, .agentRead(paneID: "w4:p2"), .agentFocus(paneID: "w4:p2"),
    ]

    @Test func everyCommandHasExactlyThePinnedArguments() {
        for command in everyCommand {
            #expect(command.arguments == pinned(command))
        }
    }

    @Test func nothingWritesToAgentsOrChangesLayout() {
        let forbidden: Set = ["prompt", "send-keys", "send-text", "start", "split", "create", "close", "rename", "move",
                              "attach", "stop", "run", "wait", "remove", "delete", "report-agent", "release-agent"]
        for command in everyCommand {
            #expect(forbidden.isDisjoint(with: command.arguments), "\(command.arguments)")
        }
    }

    @Test func onlyFocusChangesWhatTheOwnerSees() {
        #expect(everyCommand.filter(\.changesHerdrFocus) == [.agentFocus(paneID: "w4:p2")])
    }
}

@Suite("Choosing agents to link")
struct AgentLinkChoicesTests {
    private let nlpLink = HerdrLink(server: herdrServer, workspaceID: "w4", label: "NLP report", cwd: nil)
    private let agents = [agent(.idle, pane: "w3:pJ", name: nil), agent(.working, pane: "w4:p2"),
                          agent(.done, pane: "w4:pA", name: "seeds")]

    @Test func theProjectsWorkspaceComesFirstAndIsPreselected() {
        let choices = AgentLinkChoices(agents, on: herdrServer, projectLink: nlpLink, linked: [])
        #expect(choices.agents.map(\.paneID) == ["w4:p2", "w4:pA", "w3:pJ"])
        #expect(choices.preselected == ["w4:p2", "w4:pA"])
    }

    @Test func aProjectLinkFromAnotherServerInstancePreselectsNothing() {
        let stale = HerdrLink(server: restartedHerdrServer, workspaceID: "w4", label: "NLP report", cwd: nil)
        #expect(AgentLinkChoices(agents, on: herdrServer, projectLink: stale, linked: []).preselected.isEmpty)
        #expect(AgentLinkChoices(agents, on: herdrServer, projectLink: nil, linked: []).preselected.isEmpty)
    }

    @Test func agentsAlreadyLinkedToTheTaskAreLeftOut() {
        let linked = TaskAgentLink(id: 1, taskID: 1, server: herdrServer, paneID: "w4:p2", workspaceID: "w4",
                                   tabID: "w4:t2", name: "ablation", kind: "claude", label: "ablation",
                                   workspaceLabel: nil, lastStatus: .working, statusChangedAt: wednesdayMorningInBogota)
        let choices = AgentLinkChoices(agents, on: herdrServer, projectLink: nlpLink, linked: [linked])
        #expect(choices.agents.map(\.paneID) == ["w4:pA", "w3:pJ"])
        #expect(choices.preselected == ["w4:pA"])
    }
}
