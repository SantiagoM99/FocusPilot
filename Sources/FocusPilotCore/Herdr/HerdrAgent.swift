import Foundation

/// One agent as `herdr agent list` reports it. Pane IDs such as "w4:p2" are
/// only meaningful together with the `HerdrServer` that issued them, and the
/// agent in a pane can be replaced at any time.
public struct HerdrAgent: Equatable, Hashable, Sendable, Identifiable {
    public var paneID: String
    public var workspaceID: String
    public var tabID: String
    /// The owner's name for the agent, if one was given in Herdr.
    public var name: String?
    /// Which agent program it is, such as "claude" or "codex".
    public var kind: String
    public var status: HerdrAgentStatus
    /// The agent's terminal title, which agents use for a one-line summary.
    public var title: String?

    public var id: String { paneID }

    public init(paneID: String, workspaceID: String, tabID: String, name: String?, kind: String,
                status: HerdrAgentStatus, title: String?) {
        self.paneID = paneID
        self.workspaceID = workspaceID
        self.tabID = tabID
        self.name = name
        self.kind = kind
        self.status = status
        self.title = title
    }
}

/// Herdr's lifecycle states. `done` is `idle` not yet seen through a focus.
public enum HerdrAgentStatus: String, Sendable, Codable, CaseIterable {
    case working, blocked, idle, done, unknown

    /// Anything Herdr adds later reads as unknown, never as finished.
    init(herdr value: String) {
        self = Self(rawValue: value) ?? .unknown
    }

    public var activity: AgentActivity {
        switch self {
        case .working: .working
        case .blocked: .blocked
        case .idle, .done: .ready
        case .unknown: .unknown
        }
    }
}

/// The four states FocusPilot shows for an agent.
public enum AgentActivity: Sendable {
    case working
    /// Herdr recognized an approval or question; FocusPilot never answers it.
    case blocked
    /// Ready for input. This says nothing about whether the task is done.
    case ready
    /// An agent is present but Herdr cannot classify it.
    case unknown
}

/// What FocusPilot can currently see of Herdr's agents.
public enum HerdrAgents: Equatable, Sendable {
    case connected(HerdrServer, [HerdrAgent])
    case disconnected(HerdrUnavailable)
}

/// Pane IDs are passed to `agent read` and `agent focus` as arguments, so
/// only Herdr's own shape is accepted and nothing can pass as an option.
enum HerdrPaneID {
    static func isValid(_ id: String) -> Bool {
        id.wholeMatch(of: /w[A-Za-z0-9]+:p[A-Za-z0-9]+/) != nil
    }
}

/// Parses `herdr agent list` output. The reply is untrusted: any field of
/// the wrong type, or a pane ID of the wrong shape, rejects the whole reply.
enum HerdrAgentList {
    static func parse(_ data: Data) -> [HerdrAgent]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let items = result["agents"] as? [[String: Any]]
        else { return nil }
        var agents: [HerdrAgent] = []
        for item in items {
            guard let pane = item["pane_id"] as? String, HerdrPaneID.isValid(pane),
                  let workspace = item["workspace_id"] as? String, let tab = item["tab_id"] as? String,
                  let kind = item["agent"] as? String, let status = item["agent_status"] as? String,
                  optional(item["name"], String.self), optional(item["terminal_title_stripped"], String.self)
            else { return nil }
            let title = (item["terminal_title_stripped"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            agents.append(HerdrAgent(paneID: pane, workspaceID: workspace, tabID: tab, name: item["name"] as? String,
                                     kind: kind, status: HerdrAgentStatus(herdr: status), title: title))
        }
        return agents
    }

    /// True when the value is absent or of the expected type.
    private static func optional<T>(_ value: Any?, _ type: T.Type) -> Bool {
        value == nil || value is T
    }
}

/// What a change of an agent's status means for the Review queue.
public enum AgentTransition {
    public enum Review: String, Sendable, Codable {
        /// It was seen working (or blocked) and is now ready.
        case finished
        /// It is waiting at an approval or question.
        case approval
    }

    /// Only changes FocusPilot itself observed count, and unknown never does:
    /// an agent first seen ready, or ready again, produced nothing new.
    static func review(from previous: HerdrAgentStatus?, to current: HerdrAgentStatus) -> Review? {
        switch current {
        case .blocked: previous == .blocked ? nil : .approval
        case .idle, .done: previous == .working || previous == .blocked ? .finished : nil
        case .working, .unknown: nil
        }
    }

    /// The status to remember: unknown keeps the last one Herdr was sure of,
    /// so working, then unknown, then ready still counts as finishing.
    static func lastKnown(previous: HerdrAgentStatus?, current: HerdrAgentStatus) -> HerdrAgentStatus? {
        current == .unknown ? previous : current
    }
}
