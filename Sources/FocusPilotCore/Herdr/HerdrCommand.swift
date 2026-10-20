/// Every Herdr command FocusPilot is able to run. Herdr is read, and the one
/// exception is `agentFocus`, which only Open agent runs after the owner's
/// click. There is deliberately no case that creates, renames or closes
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

    var arguments: [String] {
        switch self {
        case .status: ["status", "--json"]
        case .workspaceList: ["workspace", "list"]
        case .agentList: ["agent", "list"]
        case .agentRead(let pane): ["agent", "read", pane, "--source", "visible"]
        case .agentFocus(let pane): ["agent", "focus", pane]
        }
    }

    var changesHerdrFocus: Bool {
        if case .agentFocus = self { true } else { false }
    }
}
