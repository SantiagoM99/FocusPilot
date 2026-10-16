/// Every Herdr command FocusPilot is able to run. Herdr is only ever read:
/// there is deliberately no case that creates, renames, focuses or closes a
/// workspace, or that talks to an agent.
enum HerdrCommand: CaseIterable {
    case workspaceList

    var arguments: [String] {
        switch self {
        case .workspaceList: ["workspace", "list"]
        }
    }
}
