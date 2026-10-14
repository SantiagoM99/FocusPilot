import Foundation

/// The deterministic focus engine: a pure function of the current session, an
/// event and the current instant. It performs no I/O and never reads the
/// system clock; the coordinator supplies `now` and performs the effects.
public enum FocusEngine {
    public static func handle(
        _ event: FocusEvent, session: FocusSession?, at now: Date
    ) throws(FocusEngineError) -> FocusTransition {
        if case .start(let request) = event {
            return try start(request, replacing: session, at: now)
        }
        guard var session, !session.hasEnded else { throw .noActiveSession }

        switch (event, session.phase) {
        case (.pause, .running):
            session.phase = .paused(since: now)
        case (.resume, .paused):
            session.phase = .running
        case (.startBreak(let duration), .running):
            guard duration > 0 else { throw .nonPositiveDuration }
            session.phase = .onBreak(until: now.addingTimeInterval(duration))
        case (.endBreak, .onBreak):
            session.phase = .running
        case (.complete, _):
            session.phase = .ended(at: now, reason: .completed)
        default:
            throw .notAllowed(event, in: session.phase)
        }
        return changed(to: session)
    }

    private static func start(
        _ request: SessionRequest, replacing current: FocusSession?, at now: Date
    ) throws(FocusEngineError) -> FocusTransition {
        if let current, !current.hasEnded { throw .sessionAlreadyActive }
        guard request.duration > 0 else { throw .nonPositiveDuration }
        let started = FocusSession(
            id: request.id, taskID: request.taskID, action: request.action, mode: request.mode,
            startedAt: now, plannedEnd: now.addingTimeInterval(request.duration), phase: .running
        )
        return changed(to: started)
    }

    private static func changed(to session: FocusSession) -> FocusTransition {
        FocusTransition(session: session, effects: [.persist(session), .publishPolicy(policy(for: session))])
    }

    /// Session rules apply only while the session runs; pauses and breaks lift them.
    static func policy(for session: FocusSession) -> SessionPolicy? {
        guard session.phase == .running else { return nil }
        return SessionPolicy(sessionID: session.id, mode: session.mode, end: session.plannedEnd)
    }
}
