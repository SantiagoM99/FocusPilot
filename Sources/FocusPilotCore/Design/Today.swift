import Foundation

extension TodayItem {
    /// The Now card's line: "NLP report · Next: write the comparison table".
    public func nowLine(showsProject: Bool) -> String? {
        Self.joined([showsProject ? projectTitle : nil, nextAction.map { "Next: \($0)" }])
    }

    /// Under the title in Start focus: "NLP report · Due Fri 23:59".
    public func focusSummary(at now: Date) -> String? {
        Self.joined([projectTitle, deadline.map { DeadlineText($0).relative(at: now) }])
    }

    private static func joined(_ parts: [String?]) -> String? {
        let present = parts.compactMap(\.self)
        return present.isEmpty ? nil : present.joined(separator: " · ")
    }
}

/// What the task inspector shows (#71).
public enum TaskInspection {
    /// The selected task; if none is selected or it has left the list, Now,
    /// then the first task, so the column keeps showing a task after Done.
    public static func shownTask(selection: Int64?, in items: [TodayItem]) -> TodayItem? {
        items.first { $0.id == selection } ?? items.first { $0.status == .now } ?? items.first
    }

    /// The Workspace row: the folder of the project's Herdr workspace, else
    /// the first linked folder that can be found.
    public static func workspace(herdr: HerdrLink?, resources: [ResourceStatus],
                                 home: String = NSHomeDirectory()) -> String? {
        let folder = herdr?.cwd ?? resources.lazy.compactMap { status -> String? in
            switch status.folder {
            case .healthy(let path), .moved(let path, _): path
            default: nil
            }
        }.first
        return folder.map { ResourceText.path($0, home: home) }
    }
}

/// The status line on the inspector's Herdr agent card (#71).
public struct AgentCardStatus: Equatable, Sendable {
    public enum Tone: Sendable {
        case accent, green, amber
        /// A hollow grey dot: never shown as done.
        case unknown
    }

    public var title: String
    public var tone: Tone

    public init(title: String, tone: Tone) {
        self.title = title
        self.tone = tone
    }

    /// `pending` is what waits in the Review queue for this agent. An agent
    /// that cannot be seen says so first, because Open agent will not work.
    public init(_ state: AgentLinkState, pending: [AgentTransition.Review]) {
        switch state {
        case .renamed(let agent): self.init(title: "Renamed in Herdr to “\(agent.name ?? agent.kind)”", tone: .amber)
        case .replaced: self.init(title: "Another agent in this pane", tone: .amber)
        case .notFound: self.init(title: "Not found in Herdr", tone: .amber)
        case .unknown: self.init(title: "Herdr unavailable", tone: .unknown)
        case .live(let agent):
            if pending.contains(.approval) || agent.status.activity == .blocked {
                self.init(title: "Needs approval", tone: .amber)
            } else if pending.contains(.finished) {
                self.init(title: "Results ready", tone: .green)
            } else {
                switch agent.status.activity {
                case .working: self.init(title: "Working", tone: .accent)
                case .ready: self.init(title: "Ready", tone: .green)
                case .blocked, .unknown: self.init(title: "Unknown", tone: .unknown)
                }
            }
        }
    }
}
