import Foundation
import Testing
@testable import FocusPilotCore

@Suite("SessionText")
struct SessionTextTests {
    private let start = wednesdayMorningInBogota

    private func session(_ phase: SessionPhase, mode: SessionMode = .normal, minutes: Double = 25) -> FocusSession {
        FocusSession(id: UUID(), taskID: 1, action: "Explain baseline results", mode: mode,
                     startedAt: start, plannedEnd: start.addingTimeInterval(minutes * 60), phase: phase)
    }

    @Test func phasesHaveShortLabels() {
        #expect(SessionText(session(.running)).phase == "Focusing")
        #expect(SessionText(session(.paused(since: start))).phase == "Paused")
        #expect(SessionText(session(.onBreak(until: start))).phase == "On a break")
        #expect(SessionText(session(.ended(at: start, reason: .completed))).phase == "Ended")
    }

    @Test func timeLeftCountsToThePlannedEndEvenWhilePaused() {
        let paused = SessionText(session(.paused(since: start)))

        #expect(paused.timeLeft(at: start.addingTimeInterval(52)) == "24:08")
        #expect(paused.timeLeft(at: start.addingTimeInterval(40 * 60)) == "0:00")
    }

    @Test func reducedMotionShowsWholeMinutesLeft() {
        let text = SessionText(session(.running))

        #expect(text.minutesLeft(at: start.addingTimeInterval(52)) == "25 min left")
        #expect(text.minutesLeft(at: start.addingTimeInterval(24 * 60 + 30)) == "1 min left")
        #expect(text.minutesLeft(at: start.addingTimeInterval(25 * 60)) == "0 min left")
    }

    @Test func plannedEndIsShownInTheMacZone() {
        #expect(SessionText.endsAt(start.addingTimeInterval(50 * 60), from: start, timeZone: bogota, clock: .twentyFourHour)
            == "Ends at 10:50 · Bogotá")
        #expect(SessionText.endsAt(start.addingTimeInterval(14 * 3600), from: start, timeZone: bogota, clock: .twentyFourHour)
            == "Ends tomorrow at 00:00 · Bogotá")
        #expect(SessionText.endsAt(start.addingTimeInterval(50 * 60), from: start, timeZone: bogota, clock: .twelveHour)
            == "Ends at 10:50 AM · Bogotá")
    }

    @Test func earlyEndCountdownSaysWhenEndingIsPossible() {
        let availableAt = start.addingTimeInterval(60)

        #expect(SessionText.earlyEnd(availableAt: availableAt, now: start.addingTimeInterval(18)) == "You can end it in 0:42")
        #expect(SessionText.earlyEnd(availableAt: availableAt, now: availableAt) == "You can end it now")
    }

    // #56: what a session covers, as the menu, panel and blocked pages name it.
    @Test func theScopeNamesItsProjects() {
        let projects = ["FocusPilot", "NLP report", "Thesis"].enumerated().map { ScopedProject(id: Int64($0), title: $1) }

        #expect(SessionText.scope(.allProjects) == "All projects")
        #expect(SessionText.scope(SessionScope(projects: Array(projects.prefix(1)))) == "FocusPilot")
        #expect(SessionText.scope(SessionScope(projects: Array(projects.prefix(2)))) == "FocusPilot and NLP report")
        #expect(SessionText.scope(SessionScope(projects: projects)) == "FocusPilot, NLP report and Thesis")
        #expect(SessionText.covers(.allProjects) == "Covers all projects")
        #expect(SessionText.covers(SessionScope(projects: Array(projects.prefix(2)))) == "Covers FocusPilot and NLP report")
    }

    @Test func anyTaskIsInsideASessionOnAllProjects() {
        #expect(SessionText.outsideNote(.allProjects, projectID: 4) == nil)
        #expect(SessionText.outsideNote(SessionScope(projects: [ScopedProject(id: 3, title: "NLP report")]), projectID: nil)
            == "Outside this session's projects")
    }

    @Test func withNothingInNowTheSessionIsNamedByItsScope() {
        #expect(SessionText(.sample(taskID: 1, action: "Explain baseline results")).subject == "Explain baseline results")
        #expect(SessionText(.sample(taskID: nil, action: nil)).subject == "All projects")
    }
}
