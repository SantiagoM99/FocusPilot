import Testing
@testable import FocusPilotCore

@Suite("Herdr poll schedule")
struct HerdrPollScheduleTests {
    @Test func pollsEveryFiveSecondsWhileConnected() {
        var schedule = HerdrPollSchedule()
        #expect(schedule.delay(after: .connected(herdrServer, [])) == .seconds(5))
        #expect(schedule.delay(after: .connected(herdrServer, [])) == .seconds(5))
    }

    @Test func backsOffUpToAMinuteWhileHerdrIsUnreachable() {
        var schedule = HerdrPollSchedule()
        let delays = (0..<6).map { _ in schedule.delay(after: .disconnected(.binaryNotFound)) }
        #expect(delays == [.seconds(5), .seconds(10), .seconds(20), .seconds(40), .seconds(60), .seconds(60)])
    }

    @Test func reconnectingResetsTheDelay() {
        var schedule = HerdrPollSchedule()
        for _ in 0..<4 { _ = schedule.delay(after: .disconnected(.notRunning)) }
        #expect(schedule.delay(after: .connected(herdrServer, [])) == .seconds(5))
        #expect(schedule.delay(after: .disconnected(.notRunning)) == .seconds(5))
    }
}
