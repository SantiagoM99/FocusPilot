/// Every Herdr command FocusPilot is able to run. Herdr is read; the
/// exceptions are `agentFocus`, which only Open agent runs, `tabFocus`,
/// which only Open context runs for a project's workspace, and
/// `agentPrompt`, which only Accept on an agent report runs (#67, decision
/// 0004, Phase 2 start), each after the owner's click. There is deliberately no case that creates, renames or closes
/// anything, or that sends input to an agent. `HerdrCommandAllowlistTests`
/// pins this list.
enum HerdrCommand: Equatable {
    /// Server state, version and protocol, checked before anything else.
    case status
    case workspaceList
    case agentList
    /// The agent's visible screen only: `recent` sources can scroll the
    /// agent's viewport to collect history (spike S4).
    case agentRead(paneID: String)
    /// Moves Herdr's single shared focus and marks the agent seen.
    case agentFocus(paneID: String)
    /// The workspace's tabs in Herdr's order, to find its first.
    case tabList(workspaceID: String)
    /// Moves Herdr's shared focus to the tab (S4: works from a GUI app, and
    /// marks a finished agent in that tab as seen).
    case tabFocus(tabID: String)
    /// Submits the text to the agent: the one Herdr write. The text is the
    /// report's message exactly as the owner saw it, as one argument.
    case agentPrompt(paneID: String, text: String)

    var arguments: [String] {
        switch self {
        case .status: ["status", "--json"]
        case .workspaceList: ["workspace", "list"]
        case .agentList: ["agent", "list"]
        case .agentRead(let pane): ["agent", "read", pane, "--source", "visible"]
        case .agentFocus(let pane): ["agent", "focus", pane]
        case .tabList(let workspace): ["tab", "list", "--workspace", workspace]
        case .tabFocus(let tab): ["tab", "focus", tab]
        case .agentPrompt(let pane, let text): ["agent", "prompt", pane, text]
        }
    }

    var changesHerdrFocus: Bool {
        switch self {
        case .agentFocus, .tabFocus: true
        case .status, .workspaceList, .agentList, .agentRead, .tabList, .agentPrompt: false
        }
    }

    var writesToAgent: Bool {
        if case .agentPrompt = self { true } else { false }
    }
}
