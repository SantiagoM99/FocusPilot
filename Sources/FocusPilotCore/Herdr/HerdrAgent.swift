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
/// Every text field is shown or stored, so each is made plain and cut; a
/// kind, workspace or tab with nothing visible left rejects the reply.
enum HerdrAgentList {
    static let maximumTitleLength = 200
    static let maximumNameLength = 64
    static let maximumIDLength = 64

    static func parse(_ data: Data) -> [HerdrAgent]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let items = result["agents"] as? [[String: Any]]
        else { return nil }
        var agents: [HerdrAgent] = []
        for item in items {
            guard let pane = item["pane_id"] as? String, HerdrPaneID.isValid(pane),
                  let workspace = (item["workspace_id"] as? String).flatMap({ cut($0, maximumIDLength) }),
                  let tab = (item["tab_id"] as? String).flatMap({ cut($0, maximumIDLength) }),
                  let kind = (item["agent"] as? String).flatMap({ cut($0, maximumNameLength) }),
                  let status = item["agent_status"] as? String,
                  optional(item["name"], String.self), optional(item["terminal_title_stripped"], String.self)
            else { return nil }
            let title = (item["terminal_title_stripped"] as? String).flatMap { cut($0, maximumTitleLength) }
            let name = (item["name"] as? String).flatMap { cut($0, maximumNameLength) }
            agents.append(HerdrAgent(paneID: pane, workspaceID: workspace, tabID: tab, name: name,
                                     kind: kind, status: HerdrAgentStatus(herdr: status), title: title))
        }
        return agents
    }

    private static func cut(_ text: String, _ length: Int) -> String? {
        let plain = PlainText.removingInvisibles(text).trimmingCharacters(in: .whitespaces)
        return plain.isEmpty ? nil : String(plain.prefix(length))
    }

    /// True when the value is absent or of the expected type.
    private static func optional<T>(_ value: Any?, _ type: T.Type) -> Bool {
        value == nil || value is T
    }
}

extension HerdrAgents {
    /// The same reading with terminal titles left out, to tell whether
    /// anything but a title changed.
    public var ignoringTitles: HerdrAgents {
        guard case .connected(let server, let agents) = self else { return self }
        return .connected(server, agents.map { var agent = $0; agent.title = nil; return agent })
    }
}

/// Text from a terminal made safe to show as is.
enum PlainText {
    /// Removes control characters (except tab) and format characters: bidi
    /// overrides and isolates could reorder what is shown, and zero-width
    /// characters hide text.
    static func removingInvisibles(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .control: scalar == "\t"
            case .format: false
            default: true
            }
        }))
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
