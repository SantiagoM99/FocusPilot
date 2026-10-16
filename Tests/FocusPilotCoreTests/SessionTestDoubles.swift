import Foundation
@testable import FocusPilotCore

/// Keeps every policy the coordinator publishes, in order.
actor RecordingPolicyPublisher: PolicyPublisher {
    private(set) var published: [PublishedPolicy] = []

    func publish(_ policy: PublishedPolicy) async {
        published.append(policy)
    }
}

/// Keeps every notice the coordinator delivers, in order.
actor RecordingNoticeSink: FocusNoticeSink {
    private(set) var delivered: [FocusNotice] = []

    func deliver(_ notice: FocusNotice) async {
        delivered.append(notice)
    }
}

/// A coordinator over a fresh database with a pinned Now task, a movable
/// clock and recording publisher and notices.
struct SessionFixture {
    let location: StorageLocation
    let clock: SettableClock
    let publisher = RecordingPolicyPublisher()
    let notices = RecordingNoticeSink()
    let coordinator: FocusCoordinator

    init(at start: Date = wednesdayMorningInBogota) async throws {
        location = StorageLocation(directory: try makeTemporaryDirectory())
        clock = SettableClock(start)
        coordinator = try Self.coordinator(at: location, clock: clock, publisher: publisher, notices: notices)
        try await coordinator.capture(NewTask(title: "Explain baseline results"))
        let id = try await coordinator.todayTasks()[0].id
        try await coordinator.moveTask(id, to: .now, .top)
    }

    /// A second coordinator on the same database, as after quitting and relaunching.
    func relaunched() throws -> FocusCoordinator {
        try Self.coordinator(at: location, clock: clock, publisher: publisher, notices: notices)
    }

    func advance(minutes: Double) {
        clock.set(clock.now.addingTimeInterval(minutes * 60))
    }

    private static func coordinator(at location: StorageLocation, clock: SettableClock,
                                    publisher: RecordingPolicyPublisher, notices: RecordingNoticeSink) throws -> FocusCoordinator {
        let now: @Sendable () -> Date = { clock.now }
        return FocusCoordinator(repository: try TaskRepository(location: location, now: now),
                                publisher: publisher, notices: notices, now: now)
    }
}
