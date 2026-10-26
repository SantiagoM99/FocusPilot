import Foundation

/// Turns what is in front, and session changes, into raw activity spans and
/// pilot events (#21). A pure state machine: the app reports the front app,
/// Chrome's front-tab domain while observing and each session it sees.
///
/// A distraction is a site or app any block rule names, whatever its
/// activation, so observing without enforcing still counts visits. Resume
/// time runs from a session start or resume to the first app or site in
/// front that is neither FocusPilot nor a distraction (0 if one already is).
public struct ActivityTracker: Sendable {
    static let chromeBundleID = "com.google.Chrome"

    private let ownBundleID: String?
    private var distractingDomains: [String] = []
    private var distractingApps: Set<String> = []

    private var frontApp: String?
    private var chromeDomain: String?
    private var current: (key: ActivityKey, start: Date, session: FocusSession?)?

    private var seenSessions = false
    private var session: FocusSession?
    private var resumeSince: Date?

    public init(ownBundleID: String?) {
        self.ownBundleID = ownBundleID?.lowercased()
    }

    public mutating func classify(rules: [BlockRuleSet]) {
        let targets = rules.flatMap(\.targets)
        distractingDomains = targets.compactMap { if case .site(let domain) = $0 { domain } else { nil } }
        distractingApps = Set(targets.compactMap { if case .app(let id, _) = $0 { id.lowercased() } else { nil } })
    }

    /// `nil` when nothing is in front, e.g. the Mac is asleep or locked.
    public mutating func frontApp(_ bundleID: String?, at now: Date) -> ActivityRecord {
        frontApp = bundleID
        return moved(at: now)
    }

    /// Chrome's front-tab domain, or nil when Chrome's window lost focus or
    /// the tab is not a web page. Reports arrive a moment late, so a span
    /// never starts before the one it follows.
    public mutating func chromeTab(_ domain: String?, at now: Date) -> ActivityRecord {
        chromeDomain = domain
        return moved(at: max(now, current?.start ?? now))
    }

    public mutating func session(_ new: FocusSession?, at now: Date) -> ActivityRecord {
        defer { session = new; seenSessions = true }
        guard seenSessions else { return ActivityRecord() }
        var record = ActivityRecord()
        let old = session
        if let new, new.id != old?.id, !new.hasEnded {
            record.events.append(event(.sessionStarted, at: new.startedAt, session: new))
        }
        if let new, new.id == old?.id, case .ended(let endedAt, _) = new.phase, old?.hasEnded == false {
            record.events.append(event(.sessionEnded, at: endedAt, duration: endedAt.timeIntervalSince(new.startedAt), session: new))
        }
        let wasRunning = old?.phase == .running && old?.id == new?.id
        if new?.phase == .running, !wasRunning {
            resumeSince = new?.id == old?.id ? now : new?.startedAt
            session = new
            record.events += resumedIfWorking(at: resumeSince ?? now)
        } else if new?.phase != .running {
            resumeSince = nil
        }
        return record
    }

    // MARK: Spans

    private var key: ActivityKey? {
        guard let frontApp else { return nil }
        if frontApp == Self.chromeBundleID, let chromeDomain { return .site(domain: chromeDomain) }
        return .app(bundleID: frontApp)
    }

    private mutating func moved(at now: Date) -> ActivityRecord {
        let key = key
        guard key != current?.key else { return ActivityRecord() }
        var record = ActivityRecord()
        if let current, now > current.start {
            record.spans.append(ActivitySpan(key: current.key, start: current.start, end: now))
            if let target = distraction(current.key) {
                record.events.append(event(.distractionVisit, at: current.start, duration: now.timeIntervalSince(current.start),
                                           target: target, session: current.session))
            }
        }
        current = key.map { ($0, now, session?.hasEnded == false ? session : nil) }
        record.events += resumedIfWorking(at: now)
        return record
    }

    // MARK: Classification

    /// The rule's own target for a distracting key: "youtube.com" for m.youtube.com.
    private func distraction(_ key: ActivityKey) -> String? {
        switch key {
        case .site(let domain): distractingDomains.first { SiteDomain.domain(domain, isWithin: $0) }
        case .app(let id): distractingApps.contains(id.lowercased()) ? id : nil
        }
    }

    private func isWork(_ key: ActivityKey) -> Bool {
        if case .app(let id) = key, id.lowercased() == ownBundleID { return false }
        return distraction(key) == nil
    }

    private mutating func resumedIfWorking(at now: Date) -> [PilotEvent] {
        guard let since = resumeSince, let key, isWork(key) else { return [] }
        resumeSince = nil
        return [event(.resume, at: since, duration: max(0, now.timeIntervalSince(since)), session: session)]
    }

    private func event(_ kind: PilotEvent.Kind, at: Date, duration: TimeInterval? = nil, target: String? = nil,
                       session: FocusSession?) -> PilotEvent {
        PilotEvent(kind: kind, at: at, duration: duration, target: target, sessionID: session?.id, taskID: session?.taskID)
    }
}
