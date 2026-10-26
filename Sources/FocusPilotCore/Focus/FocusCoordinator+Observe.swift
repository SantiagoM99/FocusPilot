import Foundation

public enum ObserveError: Error, Equatable {
    /// Observing would lift the strict session's blocking at once.
    case strictSession
}

/// Observe-only mode and pilot metrics (#21). Observing turns off blocking
/// and app hiding but keeps sessions and recording; the rules are kept and
/// apply again as soon as it is turned off.
extension FocusCoordinator {
    public func setObserveOnly(_ on: Bool) async throws {
        if on, let session, !session.hasEnded, session.mode == .strict, observeSince == nil {
            throw ObserveError.strictSession
        }
        await publish(try await repository.setObserveOnly(on))
    }

    public func record(_ record: ActivityRecord) async throws {
        try await repository.record(record)
    }

    public func pilotEvents(since: Date) async throws -> [PilotEvent] {
        try await repository.events(since: since)
    }

    public func pruneRawActivity() async throws {
        try await repository.pruneRawActivity()
    }
}
