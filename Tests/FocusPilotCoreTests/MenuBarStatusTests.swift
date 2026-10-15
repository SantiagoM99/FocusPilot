import Foundation
import Testing
@testable import FocusPilotCore

@Suite("Menu bar status")
struct MenuBarStatusTests {
    private let start = FocusSession.sampleStart
    /// 52 s after the start, 24:08 of the 25 minutes remain.
    private var now: Date { start.addingTimeInterval(52) }

    private func status(_ snapshot: FocusSnapshot, showsTime: Bool = false) -> MenuBarStatus {
        MenuBarStatus(snapshot: snapshot, now: now, showsTime: showsTime)
    }

    // MARK: Glyph by state

    @Test func idleWithoutASession() {
        #expect(status(FocusSnapshot()).glyph == .idle)
    }

    @Test func focusingWhileTheSessionRuns() {
        #expect(status(FocusSnapshot(session: .sample(phase: .running))).glyph == .focusing)
    }

    @Test func pausedWhileTheSessionIsPaused() {
        #expect(status(FocusSnapshot(session: .sample(phase: .paused(since: start)))).glyph == .paused)
    }

    @Test func breaksShowAsPaused() {
        let onBreak = FocusSnapshot(session: .sample(phase: .onBreak(until: start.addingTimeInterval(300))))
        #expect(status(onBreak).glyph == .paused)
    }

    @Test func anEndedSessionIsIdle() {
        let ended = FocusSnapshot(session: .sample(phase: .ended(at: start, reason: .completed)))
        #expect(status(ended).glyph == .idle)
    }

    @Test func observeOnlyWithoutASession() {
        #expect(status(FocusSnapshot(isObserveOnly: true)).glyph == .observing)
    }

    @Test func anActiveSessionTakesPrecedenceOverObserveOnly() {
        let snapshot = FocusSnapshot(session: .sample(phase: .running), isObserveOnly: true)
        #expect(status(snapshot).glyph == .focusing)
    }

    // MARK: Time label

    @Test func timeIsHiddenUnlessTheOwnerTurnsItOn() {
        #expect(status(FocusSnapshot(session: .sample(phase: .running))).timeText == nil)
    }

    @Test func timeShowsMinutesAndSecondsLeft() {
        let running = FocusSnapshot(session: .sample(phase: .running))
        #expect(status(running, showsTime: true).timeText == "24:08")
    }

    @Test func timeIsHiddenWithoutAnActiveSession() {
        #expect(status(FocusSnapshot(), showsTime: true).timeText == nil)
    }

    @Test func timeIsDimmedOnlyWhilePaused() {
        let paused = FocusSnapshot(session: .sample(phase: .paused(since: start)))
        #expect(status(paused, showsTime: true).isTimeDimmed)
        #expect(!status(FocusSnapshot(session: .sample(phase: .running)), showsTime: true).isTimeDimmed)
    }

    @Test func timeNeverGoesNegative() {
        let late = MenuBarStatus(
            snapshot: FocusSnapshot(session: .sample(phase: .running)),
            now: start.addingTimeInterval(30 * 60), showsTime: true
        )
        #expect(late.timeText == "0:00")
    }

    @Test(arguments: [
        (59, "0:59"), (300, "5:00"), (3600, "1:00:00"), (3665, "1:01:05"),
    ] as [(TimeInterval, String)])
    func remainingTimeFormat(seconds: TimeInterval, expected: String) {
        #expect(MenuBarStatus.format(remaining: seconds) == expected)
    }

    // MARK: VoiceOver

    @Test func accessibilityLabelReadsEachState() {
        #expect(status(FocusSnapshot()).accessibilityLabel == "FocusPilot: No current task")
        #expect(status(FocusSnapshot(session: .sample(phase: .running))).accessibilityLabel
            == "FocusPilot: Focusing on Write the essay")
        #expect(status(FocusSnapshot(session: .sample(phase: .paused(since: start)))).accessibilityLabel
            == "FocusPilot: Paused, Write the essay")
        #expect(status(FocusSnapshot(session: .sample(phase: .onBreak(until: now)))).accessibilityLabel
            == "FocusPilot: On a break, Write the essay")
        #expect(status(FocusSnapshot(isObserveOnly: true)).accessibilityLabel
            == "FocusPilot: Observe only, No current task")
    }

    @Test func accessibilityLabelIncludesTheTimeWhenShown() {
        let running = FocusSnapshot(session: .sample(phase: .running))
        #expect(status(running, showsTime: true).accessibilityLabel
            == "FocusPilot: Focusing on Write the essay, 24:08 left")
    }
}
