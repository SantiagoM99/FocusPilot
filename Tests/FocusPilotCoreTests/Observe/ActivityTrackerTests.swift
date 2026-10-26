import Foundation
import Testing
@testable import FocusPilotCore

private let t0 = wednesdayMorningInBogota
private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

private let xcode = "com.apple.dt.Xcode"
private let chrome = "com.google.Chrome"
private let own = "com.santiagom99.focuspilot"
private let rules = [
    BlockRuleSet(targets: [.site(domain: "youtube.com"), .app(bundleID: "com.burbn.instagram", name: "Instagram")],
                 activation: .sessionOnly),
]

/// Observing, the only time front-app activity is recorded (decision 0003).
private func tracker(observing: Bool = true) -> ActivityTracker {
    var tracker = ActivityTracker(ownBundleID: own)
    tracker.classify(rules: rules)
    _ = tracker.observing(observing, at: t0)
    return tracker
}

private func session(_ phase: SessionPhase, id: UUID = sessionID) -> FocusSession {
    FocusSession(id: id, taskID: 7, action: "Write §4.2", mode: .normal, startedAt: at(0),
                 plannedEnd: at(25 * 60), phase: phase)
}

private let sessionID = UUID()

@Suite("Activity tracker")
struct ActivityTrackerTests {
    @Test func eachFrontAppIsARawSpanClosedByTheNext() {
        var t = tracker()
        _ = t.frontApp(xcode, at: at(0))

        let record = t.frontApp("com.apple.Terminal", at: at(30))

        #expect(record.spans == [ActivitySpan(key: .app(bundleID: xcode), start: at(0), end: at(30))])
        #expect(record.events.isEmpty, "Work apps are not events")
    }

    @Test func chromeInFrontIsRecordedByTheDomainItReports() {
        var t = tracker()
        _ = t.frontApp(chrome, at: at(0))
        _ = t.chromeTab("github.com", at: at(0))

        let record = t.chromeTab(nil, at: at(20))

        #expect(record.spans == [ActivitySpan(key: .site(domain: "github.com"), start: at(0), end: at(20))])
        #expect(t.frontApp(xcode, at: at(25)).spans == [ActivitySpan(key: .app(bundleID: chrome), start: at(20), end: at(25))])
    }

    @Test func aTabReportOlderThanChromeComingForwardStartsNoEarlier() {
        var t = tracker()
        _ = t.frontApp(chrome, at: at(10))

        let record = t.chromeTab("github.com", at: at(8))

        #expect(record.spans.isEmpty)
        #expect(t.frontApp(xcode, at: at(40)).spans == [ActivitySpan(key: .site(domain: "github.com"), start: at(10), end: at(40))])
    }

    @Test func leavingADistractionDuringASessionIsAVisitLinkedToIt() {
        var t = tracker()
        _ = t.session(session(.running), at: at(0))
        _ = t.frontApp(chrome, at: at(60))
        _ = t.chromeTab("m.youtube.com", at: at(60))

        let record = t.chromeTab("github.com", at: at(150))

        #expect(record.events == [PilotEvent(kind: .distractionVisit, at: at(60), duration: 90, target: "youtube.com",
                                             sessionID: sessionID, taskID: 7)])
    }

    @Test func aDistractionAppOutsideASessionIsAVisitWithNoLinks() {
        var t = tracker()
        _ = t.frontApp("com.burbn.instagram", at: at(0))

        let record = t.frontApp(xcode, at: at(5))

        #expect(record.events == [PilotEvent(kind: .distractionVisit, at: at(0), duration: 5, target: "com.burbn.instagram")])
    }

    @Test func nothingInFrontClosesTheSpanSoSleepIsNotCounted() {
        var t = tracker()
        _ = t.frontApp(xcode, at: at(0))

        #expect(t.frontApp(nil, at: at(10)).spans == [ActivitySpan(key: .app(bundleID: xcode), start: at(0), end: at(10))])
        #expect(t.frontApp(xcode, at: at(3600)).spans.isEmpty)
    }

    @Test func sessionsAreEventsWhenTheyStartAndEnd() {
        var t = tracker()
        _ = t.session(nil, at: at(0))

        let started = t.session(session(.running), at: at(0))
        let ended = t.session(session(.ended(at: at(1500), reason: .completed)), at: at(1500))

        #expect(started.events.first == PilotEvent(kind: .sessionStarted, at: at(0), sessionID: sessionID, taskID: 7))
        #expect(ended.events == [PilotEvent(kind: .sessionEnded, at: at(1500), duration: 1500, sessionID: sessionID, taskID: 7)])
    }

    // A session restored at launch already has its start recorded.
    @Test func theFirstSessionSeenIsNotANewStart() {
        var t = tracker()

        #expect(t.session(session(.running), at: at(600)).events.isEmpty)
    }

    @Test func resumeTimeRunsFromTheStartToTheFirstWorkAppOrSite() {
        var t = tracker()
        _ = t.session(nil, at: at(0))
        _ = t.frontApp(own, at: at(0))
        _ = t.session(session(.running), at: at(0))

        #expect(t.frontApp("com.burbn.instagram", at: at(4)).events.isEmpty, "A distraction is not resuming")
        let record = t.frontApp(xcode, at: at(12))

        #expect(record.events.contains(PilotEvent(kind: .resume, at: at(0), duration: 12, sessionID: sessionID, taskID: 7)))
        #expect(t.frontApp("com.apple.Terminal", at: at(20)).events.isEmpty, "Once per start")
    }

    @Test func alreadyInAWorkAppResumesAtOnce() {
        var t = tracker()
        _ = t.session(nil, at: at(0))
        _ = t.frontApp(xcode, at: at(0))

        let record = t.session(session(.running), at: at(0))

        #expect(record.events.contains(PilotEvent(kind: .resume, at: at(0), duration: 0, sessionID: sessionID, taskID: 7)))
    }

    @Test func resumingAfterAPauseIsTimedFromTheResume() {
        var t = tracker()
        _ = t.session(nil, at: at(0))
        _ = t.frontApp(xcode, at: at(0))
        _ = t.session(session(.running), at: at(0))
        _ = t.frontApp(own, at: at(300))
        _ = t.session(session(.paused(since: at(300))), at: at(300))

        _ = t.session(session(.running), at: at(400))
        let record = t.frontApp(xcode, at: at(409))

        #expect(record.events.contains(PilotEvent(kind: .resume, at: at(400), duration: 9, sessionID: sessionID, taskID: 7)))
    }

    @Test func pausingBeforeGettingBackToWorkRecordsNoResume() {
        var t = tracker()
        _ = t.session(nil, at: at(0))
        _ = t.frontApp(own, at: at(0))
        _ = t.session(session(.running), at: at(0))
        _ = t.session(session(.paused(since: at(30))), at: at(30))

        #expect(!t.frontApp(xcode, at: at(40)).events.contains { $0.kind == .resume })
    }

    // Review of #51: a lock screen ends the span; a wake behind it starts none.
    @Test func lockingEndsTheSpanAndWakingBehindTheLockScreenStartsNone() {
        var t = tracker()
        _ = t.frontApp(xcode, at: at(0))

        let locked = t.away(.locked, true, at: at(60))
        _ = t.away(.asleep, true, at: at(70))
        let woke = t.away(.asleep, false, at: at(4000))
        let unlocked = t.away(.locked, false, at: at(4010))

        #expect(locked.spans == [ActivitySpan(key: .app(bundleID: xcode), start: at(0), end: at(60))])
        #expect(woke.isEmpty)
        #expect(unlocked.isEmpty)
        #expect(t.frontApp(chrome, at: at(4030)).spans == [ActivitySpan(key: .app(bundleID: xcode), start: at(4010), end: at(4030))])
    }

    @Test func idleEndsTheSpanAtTheLastInput() {
        var t = tracker()
        _ = t.frontApp("com.burbn.instagram", at: at(0))

        let idle = t.away(.idle, true, at: at(100))

        #expect(idle.spans == [ActivitySpan(key: .app(bundleID: "com.burbn.instagram"), start: at(0), end: at(100))])
        #expect(idle.events.map(\.duration) == [100])
        #expect(t.away(.idle, false, at: at(700)).isEmpty)
        #expect(t.frontApp(xcode, at: at(710)).spans.first?.start == at(700))
    }

    // A forward jump of the Mac's clock is not time spent in the app.
    @Test func aForwardClockJumpCapsTheSpan() {
        var t = tracker()
        t.tick(at: at(0), uptime: .seconds(1000))
        _ = t.frontApp("com.burbn.instagram", at: at(0))

        let jumped = t.tick(at: at(3630), uptime: .seconds(1030))

        #expect(jumped.spans == [ActivitySpan(key: .app(bundleID: "com.burbn.instagram"), start: at(0), end: at(30))])
        #expect(jumped.events.map(\.duration) == [30])
        #expect(t.frontApp(xcode, at: at(3640)).spans == [ActivitySpan(key: .app(bundleID: "com.burbn.instagram"), start: at(3630), end: at(3640))])
    }

    @Test func steadyTicksChangeNothing() {
        var t = tracker()
        t.tick(at: at(0), uptime: .seconds(0))
        _ = t.frontApp(xcode, at: at(0))

        #expect(t.tick(at: at(30), uptime: .seconds(30)).isEmpty)
        #expect(t.tick(at: at(65), uptime: .seconds(60)).isEmpty, "A few seconds of drift is not a jump")
    }

    @Test func movingBetweenSubdomainsOfOneRuleIsOneVisit() {
        var t = tracker()
        _ = t.frontApp(chrome, at: at(0))
        _ = t.chromeTab("youtube.com", at: at(0))

        let moved = t.chromeTab("m.youtube.com", at: at(40))
        let left = t.chromeTab("github.com", at: at(100))

        #expect(moved.spans.count == 1, "Raw activity still has each domain")
        #expect(moved.events.isEmpty)
        #expect(left.events == [PilotEvent(kind: .distractionVisit, at: at(0), duration: 100, target: "youtube.com")])
    }

    // Owner decision (a), 2026-10-25: outside observe-only, no front-app
    // activity; only session, blocked-visit and exception events.
    @Test func outsideObserveOnlyTheFrontAppIsNotRecorded() {
        var t = tracker(observing: false)
        _ = t.session(nil, at: at(0))
        _ = t.frontApp(own, at: at(0))

        let started = t.session(session(.running), at: at(0))
        let switched = t.frontApp("com.burbn.instagram", at: at(10))
        let left = t.frontApp(xcode, at: at(40))

        #expect(started.events.map(\.kind) == [.sessionStarted], "No resume time")
        #expect(switched.isEmpty && left.isEmpty)
    }

    @Test func turningObserveOffEndsTheSpanAndTheVisit() {
        var t = tracker()
        _ = t.frontApp("com.burbn.instagram", at: at(0))

        let off = t.observing(false, at: at(20))

        #expect(off.spans == [ActivitySpan(key: .app(bundleID: "com.burbn.instagram"), start: at(0), end: at(20))])
        #expect(off.events.map(\.kind) == [.distractionVisit])
        #expect(t.frontApp(xcode, at: at(30)).isEmpty)
    }

    @Test func turningObserveOnStartsWithTheAppInFront() {
        var t = tracker(observing: false)
        _ = t.frontApp(xcode, at: at(0))

        _ = t.observing(true, at: at(50))

        #expect(t.frontApp(chrome, at: at(80)).spans == [ActivitySpan(key: .app(bundleID: xcode), start: at(50), end: at(80))])
    }

    // While blocking, a hidden app is a blocked visit, linked to the session.
    @Test func aHiddenAppIsABlockedVisit() {
        var t = tracker(observing: false)
        _ = t.session(nil, at: at(0))
        _ = t.session(session(.running), at: at(0))

        #expect(t.blockedApp("com.burbn.instagram", at: at(30))
            == PilotEvent(kind: .blockedVisit, at: at(30), target: "com.burbn.instagram", sessionID: sessionID, taskID: 7))
    }
}
