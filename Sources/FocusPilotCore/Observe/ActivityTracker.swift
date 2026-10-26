import Foundation

/// Turns what is in front, and session changes, into raw activity spans and
/// pilot events (#21). A pure state machine: the app reports the front app,
/// Chrome's front-tab domain while observing, each session it sees, when
/// the owner is away (asleep, locked or idle) and a periodic tick.
///
/// A distraction is a site or app any block rule names, whatever its
/// activation, so observing without enforcing still counts visits; moving
/// between subdomains of one rule is one visit. Resume time runs from a
/// session start or resume to the first app or site in front that is
/// neither FocusPilot nor a distraction (0 if one already is).
public struct ActivityTracker: Sendable {
    /// Why nothing counts as in front.
    public enum AwayReason: Hashable, Sendable {
        case asleep, locked, idle
    }

    /// Wall time running ahead of monotonic time by more than this between
    /// ticks is a clock change, not time in front.
    static let clockJumpTolerance: TimeInterval = 60

    private let ownBundleID: String?
    private var distractingDomains: [String] = []
    private var distractingApps: Set<String> = []

    private var frontApp: String?
    private var chromeDomain: String?
    private var away: Set<AwayReason> = []
    /// Front-app activity is recorded only while observing (decision 0003, 2026-10-25).
    private var isObserving = false
    private var current: (key: ActivityKey, start: Date)?
    private var visit: (target: String, start: Date, session: FocusSession?)?
    private var lastTick: (wall: Date, uptime: Duration)?

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

    /// `nil` when no app is in front.
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

    /// Outside observe-only nothing is in front as far as recording goes:
    /// no spans, visits or resume times, only session events.
    public mutating func observing(_ on: Bool, at now: Date) -> ActivityRecord {
        isObserving = on
        return moved(at: now)
    }

    /// While blocking: an app hidden as it came forward (decision 0003, 2026-10-25).
    public func blockedApp(_ bundleID: String, at now: Date) -> PilotEvent {
        event(.blockedVisit, at: now, target: bundleID, session: session?.hasEnded == false ? session : nil)
    }

    /// Nothing is in front while any reason holds; a wake behind the lock
    /// screen starts nothing until it is unlocked.
    public mutating func away(_ reason: AwayReason, _ isAway: Bool, at now: Date) -> ActivityRecord {
        if isAway { away.insert(reason) } else { away.remove(reason) }
        return moved(at: max(now, current?.start ?? now))
    }

    /// Called every few seconds with monotonic time. After a forward jump
    /// of the Mac's clock, the current span ends where monotonic time says
    /// it should and starts again now.
    @discardableResult
    public mutating func tick(at now: Date, uptime: Duration) -> ActivityRecord {
        defer { lastTick = (now, uptime) }
        guard let last = lastTick, let open = current else { return ActivityRecord() }
        let expected = last.wall.addingTimeInterval((uptime - last.uptime) / .seconds(1))
        guard now.timeIntervalSince(expected) > Self.clockJumpTolerance else { return ActivityRecord() }
        var record = close(at: max(expected, open.start))
        current = (open.key, now)
        startVisit(open.key, at: now)
        return record
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

    // MARK: Spans and visits

    private var key: ActivityKey? {
        guard isObserving, away.isEmpty, let frontApp else { return nil }
        if frontApp == ChromeExtension.chromeBundleID, let chromeDomain { return .site(domain: chromeDomain) }
        return .app(bundleID: frontApp)
    }

    private mutating func moved(at now: Date) -> ActivityRecord {
        let key = key
        guard key != current?.key else { return ActivityRecord() }
        let target = key.flatMap(distraction)
        let continuesVisit = target != nil && target == visit?.target
        var record = continuesVisit ? closeSpan(at: now) : close(at: now)
        current = key.map { ($0, now) }
        if !continuesVisit, let key { startVisit(key, at: now) }
        record.events += resumedIfWorking(at: now)
        return record
    }

    /// Ends the current span and any visit.
    private mutating func close(at end: Date) -> ActivityRecord {
        var record = closeSpan(at: end)
        if let visit, end > visit.start {
            record.events.append(event(.distractionVisit, at: visit.start, duration: end.timeIntervalSince(visit.start),
                                       target: visit.target, session: visit.session))
        }
        visit = nil
        return record
    }

    private mutating func closeSpan(at end: Date) -> ActivityRecord {
        var record = ActivityRecord()
        if let current, end > current.start {
            record.spans.append(ActivitySpan(key: current.key, start: current.start, end: end))
        }
        current = nil
        return record
    }

    private mutating func startVisit(_ key: ActivityKey, at now: Date) {
        visit = distraction(key).map { ($0, now, session?.hasEnded == false ? session : nil) }
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
