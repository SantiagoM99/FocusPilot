import Foundation
import GRDB
import Testing
@testable import FocusPilotCore

@Suite("Observe-only and pilot events in storage")
struct ObserveStorageTests {
    private let start = wednesdayMorningInBogota

    private func repository(_ clock: SettableClock) throws -> (TaskRepository, StorageLocation) {
        let location = StorageLocation(directory: try makeTemporaryDirectory())
        return (try TaskRepository(location: location, now: { clock.now }), location)
    }

    @Test func turningObserveOnIsAPolicyChangeThatRemembersWhenItStarted() async throws {
        let clock = SettableClock(start)
        let (repository, _) = try repository(clock)

        let on = try await repository.setObserveOnly(true)
        clock.set(start.addingTimeInterval(3600))
        let again = try await repository.setObserveOnly(true)
        let off = try await repository.setObserveOnly(false)

        #expect(on.inputs.observeSince == start)
        #expect(again.inputs.observeSince == start, "Already on keeps the first day")
        #expect(off.inputs.observeSince == nil)
        #expect([on.revision, again.revision, off.revision] == [Int]([1, 2, 3]))
        #expect(try await repository.policyInputs().observeSince == nil)
    }

    @Test func spansAndEventsAreStoredTogether() async throws {
        let (repository, _) = try repository(SettableClock(start))
        let session = UUID()
        let visit = PilotEvent(kind: .distractionVisit, at: start, duration: 90, target: "youtube.com",
                               sessionID: session, taskID: 7)
        let span = ActivitySpan(key: .site(domain: "m.youtube.com"), start: start, end: start.addingTimeInterval(90))

        try await repository.record(ActivityRecord(spans: [span], events: [visit]))

        #expect(try await repository.events(since: start) == [visit])
        #expect(try await repository.rawActivity() == [span])
    }

    // DATA_AND_MEMORY.md: raw activity is kept 24 hours; Events outlive it.
    @Test func pruningDeletesRawActivityOlderThanADayAndKeepsEvents() async throws {
        let clock = SettableClock(start)
        let (repository, _) = try repository(clock)
        let old = ActivitySpan(key: .app(bundleID: "com.apple.dt.Xcode"), start: start, end: start.addingTimeInterval(60))
        let recent = ActivitySpan(key: .app(bundleID: "com.apple.Terminal"), start: start.addingTimeInterval(3600),
                                  end: start.addingTimeInterval(3700))
        let event = PilotEvent(kind: .sessionStarted, at: start)
        try await repository.record(ActivityRecord(spans: [old, recent], events: [event]))

        clock.set(start.addingTimeInterval(24 * 3600 + 120))
        try await repository.pruneRawActivity()

        #expect(try await repository.rawActivity() == [recent])
        #expect(try await repository.events(since: start) == [event])
    }

    // Only a grant that stores an exception is an event; one already covered changes nothing.
    @Test func grantingAnExceptionRecordsAnEventInTheSameWriteOnlyWhenGranted() async throws {
        let (repository, _) = try repository(SettableClock(start))
        _ = try await repository.save(BlockRuleSet(targets: [.site(domain: "youtube.com")], activation: .always))
        let session = UUID()
        let exception = TimedException(scope: .site(domain: "youtube.com"), grantedAt: start,
                                       expiresAt: start.addingTimeInterval(300), sessionID: session)

        let first = try await repository.grant(exception)
        let second = try await repository.grant(exception)

        guard case .granted = first else { Issue.record("first: \(first)"); return }
        #expect(second == .alreadyCovered(expiresAt: start.addingTimeInterval(300)))
        #expect(try await repository.events(since: start) == [
            PilotEvent(kind: .exceptionGranted, at: start, duration: 300, sessionID: session),
        ])
    }

    // Decision 0003: no URLs or content. The tables have no column that could hold them.
    @Test func theTablesHoldNoURLsOrContent() async throws {
        let (_, location) = try repository(SettableClock(start))
        var configuration = Configuration()
        configuration.readonly = true
        let queue = try DatabaseQueue(path: location.ownerDatabaseURL.path, configuration: configuration)

        let columns = try await queue.read { db in
            (try db.columns(in: "pilotEvent").map(\.name), try db.columns(in: "rawActivity").map(\.name))
        }

        #expect(columns.0 == ["id", "kind", "at", "duration", "target", "sessionId", "taskId"])
        #expect(columns.1 == ["id", "kind", "target", "start", "end"])
    }
}
