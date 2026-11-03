import Foundation
import Testing
@testable import FocusPilotCore

private let now = wednesdayMorningInBogota
private func ago(minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

/// #58 (decision 0004): switches per hour, time to get back into a thread,
/// and how long agents waited for the owner, from pilot events only.
@Suite("Parallel-work metrics")
struct ParallelMetricsTests {
    private let first = UUID(), second = UUID()

    /// Two ended sessions, 2 h and 1 h, touching 4 and 2 tasks: 3 + 1 switches.
    private var sessions: [PilotEvent] {
        var events = [PilotEvent(kind: .sessionEnded, at: ago(minutes: 300), duration: 7200, sessionID: first),
                      PilotEvent(kind: .sessionEnded, at: ago(minutes: 30), duration: 3600, sessionID: second)]
        for task in 1...4 {
            events.append(PilotEvent(kind: .taskTouched, at: ago(minutes: 420 - Double(task * 20)), sessionID: first, taskID: Int64(task)))
        }
        for task in 5...6 {
            events.append(PilotEvent(kind: .taskTouched, at: ago(minutes: 80 - Double(task)), sessionID: second, taskID: Int64(task)))
        }
        return events
    }

    @Test func pickingUpTheFirstTaskIsNotASwitch() {
        let summary = WeeklySummary(events: sessions, now: now)

        #expect(summary.switches == 4)
        #expect(summary.focusTime == 3 * 3600)
        #expect(summary.line("Switches") == "1.3 per hour · 4 in 3 h")
    }

    // A session still running has no length yet, so its switches wait for its end.
    @Test func onlyEndedSessionsCount() {
        let running = (1...3).map { PilotEvent(kind: .taskTouched, at: ago(minutes: Double($0)), sessionID: UUID(), taskID: Int64($0)) }

        #expect(WeeklySummary(events: running, now: now).line("Switches") == "No sessions ended yet")
    }

    @Test func gettingBackIntoAThreadIsTheMedianTime() {
        let backIn = [20.0, 45, 300].map { PilotEvent(kind: .backIntoThread, at: ago(minutes: 5), duration: $0, taskID: 1) }

        #expect(WeeklySummary(events: backIn, now: now).line("Back into a thread") == "median 45 s · 3 switches")
        #expect(WeeklySummary(events: [], now: now).line("Back into a thread") == "No switches yet")
    }

    @Test func agentWaitsAreTheMedianAndTheLongest() {
        let waits = [4.0, 14, 52].map { PilotEvent(kind: .agentWait, at: ago(minutes: 10), duration: $0 * 60, target: "finished") }

        #expect(WeeklySummary(events: waits, now: now).line("Agents waiting for you")
            == "median 14 min · longest 52 min · 3 results and requests")
        #expect(WeeklySummary(events: [], now: now).line("Agents waiting for you") == "None yet")
    }

    @Test func theNewLinesFollowTheBaselineOnes() {
        #expect(WeeklySummary(events: [], now: now).lines.map(\.label) == [
            "Focus sessions", "Resume time", "Distraction visits", "Blocked visits", "Exceptions",
            "Switches", "Back into a thread", "Agents waiting for you",
        ])
    }
}

private extension WeeklySummary {
    func line(_ label: String) -> String? {
        lines.first { $0.label == label }?.value
    }
}
