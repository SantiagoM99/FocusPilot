import Foundation
import Testing
@testable import FocusPilotCore

/// The app quits mid-session (#15), end to end on the app's side: the real
/// coordinator publishes through the mailbox, the real host reads it and
/// tells the extension the app stopped, and a relaunch after the planned end
/// publishes the end. What the host sends is pinned in
/// `Tests/ChromeExtension/fixtures/quit-mid-session.json`, which the
/// extension's end-to-end test replays through its service worker.
@Suite("Session end without the app")
struct SessionWithoutAppTests {
    static let fixture = ChromeContractTests.fixture.deletingLastPathComponent().appending(path: "quit-mid-session.json")

    /// One step of the story: when it happens and what the host sends then.
    struct Step {
        var name: String
        var at: Date
        var frames: [[String: Any]]
    }

    /// Starts a 25-minute session with a session-only and an always-on rule,
    /// quits the app 10 minutes in and relaunches it 20 minutes after the end.
    static func quitMidSession(_ mode: SessionMode) async throws -> [Step] {
        let location = StorageLocation(directory: try makeTemporaryDirectory())
        let clock = SettableClock(wednesdayMorningInBogota)
        let appRunning = Locked(true)
        let frames = Locked<[Data]>([])
        let host = ChromeHost(location: location, environment: ChromeHost.Environment(
            isAppRunning: { appRunning.withLock { $0 } }, openApp: {}, now: { clock.now }, processID: 4242,
            send: { data in frames.withLock { $0.append(data) } }))
        var steps: [Step] = []
        func step(_ name: String) {
            let sent = frames.withLock { taken in defer { taken = [] }; return taken }
            steps.append(Step(name: name, at: clock.now, frames: sent.map { normalized($0) }))
        }

        let app = try coordinator(location, clock)
        try await app.saveRuleSet(BlockRuleSet(targets: [.site(domain: "youtube.com")], activation: .sessionOnly))
        try await app.saveRuleSet(BlockRuleSet(targets: [.site(domain: "instagram.com")], activation: .always))
        try await app.capture(NewTask(title: "Explain baseline results"))
        try await app.moveTask(try await app.todayTasks()[0].id, to: .now, .top)
        try await app.startSession(duration: 25 * 60, mode: mode)
        host.receive(try JSONSerialization.data(withJSONObject: [
            "type": "hello", "profileId": HostHarness.profile, "incognitoAllowed": false, "allSitesAccess": true]))
        step("session-started")

        clock.set(clock.now.addingTimeInterval(10 * 60))
        appRunning.withLock { $0 = false }
        host.poll()
        step("app-quit")

        clock.set(clock.now.addingTimeInterval(16 * 60))
        host.poll()
        step("past-planned-end")

        clock.set(clock.now.addingTimeInterval(19 * 60))
        appRunning.withLock { $0 = true }
        try await coordinator(location, clock).launch()
        host.poll()
        step("app-relaunched")
        return steps
    }

    private static func coordinator(_ location: StorageLocation, _ clock: SettableClock) throws -> FocusCoordinator {
        let now: @Sendable () -> Date = { clock.now }
        return FocusCoordinator(repository: try TaskRepository(location: location, now: now),
                                publisher: ChromePolicyMailbox(location: location), now: now)
    }

    /// Sources and session IDs are random, and the checksum covers the
    /// session ID; the fixture keeps placeholders, which the extension never checks.
    private static func normalized(_ frame: Data) -> [String: Any] {
        var object = (try? JSONSerialization.jsonObject(with: frame)) as? [String: Any] ?? [:]
        if object["source"] != nil { object["source"] = "source" }
        if var policy = object["policy"] as? [String: Any] {
            policy["checksum"] = "checksum"
            if var session = policy["session"] as? [String: Any] {
                session["sessionID"] = "session"
                policy["session"] = session
            }
            object["policy"] = policy
        }
        return object
    }

    private func policies(_ step: Step) -> [[String: Any]] {
        step.frames.filter { $0["type"] as? String == "policy" }.compactMap { $0["policy"] as? [String: Any] }
    }

    private func statuses(_ step: Step) -> [Bool?] {
        step.frames.filter { $0["type"] as? String == "status" }.map { $0["appRunning"] as? Bool }
    }

    @Test(arguments: [SessionMode.normal, .strict])
    func theExtensionKeepsTheSessionPolicyWhileTheAppIsQuit(mode: SessionMode) async throws {
        let steps = try await Self.quitMidSession(mode)

        let session = try #require(policies(steps[0]).last?["session"] as? [String: Any])
        #expect(session["mode"] as? String == mode.rawValue)
        #expect(session["end"] as? String == "2026-10-14T15:25:00Z")
        #expect(statuses(steps[1]) == [false])
        // Quit, the app can't publish: the extension's last policy and its own clock decide.
        #expect(policies(steps[1]).isEmpty)
        #expect(policies(steps[2]).isEmpty)
    }

    // The relaunched app records the end and publishes a policy without the
    // session; only then does a strict session stop blocking.
    @Test(arguments: [SessionMode.normal, .strict])
    func aRelaunchAfterThePlannedEndPublishesTheEnd(mode: SessionMode) async throws {
        let steps = try await Self.quitMidSession(mode)

        let after = try #require(policies(steps[3]).last)
        #expect(after["session"] == nil)
        #expect((after["always"] as? [String: Any])?["domains"] as? [String] == ["instagram.com"])
        #expect(statuses(steps[3]) == [true])
    }

    @Test func theExtensionsReplayIsWhatTheAppSends() async throws {
        var story: [String: Any] = [:]
        for mode in [SessionMode.normal, .strict] {
            story[mode.rawValue] = try await Self.quitMidSession(mode).map {
                ["step": $0.name, "at": ISO8601DateFormatter().string(from: $0.at), "frames": $0.frames] as [String: Any]
            }
        }
        let written = try JSONSerialization.data(withJSONObject: story, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
        if ProcessInfo.processInfo.environment["FOCUSPILOT_WRITE_FIXTURES"] != nil {
            try written.write(to: Self.fixture)
        }

        let fixture = try Data(contentsOf: Self.fixture)
        let expected = try JSONSerialization.jsonObject(with: fixture) as? NSDictionary
        #expect(try JSONSerialization.jsonObject(with: written) as? NSDictionary == expected,
                "Run with FOCUSPILOT_WRITE_FIXTURES=1 after an intended change to what the host sends.")
    }
}
