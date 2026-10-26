import Foundation

/// One pilot metric (DATA_AND_MEMORY.md, Event; decision 0003): kept after
/// raw activity is deleted, so the baseline week can be compared with the
/// pilot. It holds a type, times, a duration and task and session links;
/// a distraction visit also names the domain or app bundle ID its rule
/// names. Never a URL, page title or content.
public struct PilotEvent: Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case sessionStarted, sessionEnded
        /// From a session start or resume to the first work app or site in front.
        case resume
        /// Time in front of a site or app a block rule names.
        case distractionVisit
        case exceptionGranted
    }

    public var kind: Kind
    public var at: Date
    public var duration: TimeInterval?
    /// The rule's domain ("youtube.com") or app bundle ID, for distraction visits.
    public var target: String?
    public var sessionID: UUID?
    public var taskID: Int64?

    public init(kind: Kind, at: Date, duration: TimeInterval? = nil, target: String? = nil,
                sessionID: UUID? = nil, taskID: Int64? = nil) {
        self.kind = kind
        self.at = at
        self.duration = duration
        self.target = target
        self.sessionID = sessionID
        self.taskID = taskID
    }
}

/// What was in front: a Mac app, or the domain of Chrome's front tab while
/// observing. Raw activity, deleted after 24 hours.
public enum ActivityKey: Hashable, Sendable {
    case app(bundleID: String)
    case site(domain: String)
}

public struct ActivitySpan: Equatable, Sendable {
    public var key: ActivityKey
    public var start: Date
    public var end: Date

    public init(key: ActivityKey, start: Date, end: Date) {
        self.key = key
        self.start = start
        self.end = end
    }
}

/// What one tracker input produced, for the repository to store.
public struct ActivityRecord: Equatable, Sendable {
    public var spans: [ActivitySpan] = []
    public var events: [PilotEvent] = []

    public init(spans: [ActivitySpan] = [], events: [PilotEvent] = []) {
        self.spans = spans
        self.events = events
    }

    public var isEmpty: Bool { spans.isEmpty && events.isEmpty }
}
