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

private func tracker() -> ActivityTracker {
    var tracker = ActivityTracker(ownBundleID: own)
    tracker.classify(rules: rules)
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
}
