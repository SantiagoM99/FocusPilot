import Foundation

/// The deterministic focus engine: a pure function of the current session, an
/// event and the current instant. It performs no I/O and never reads the
/// system clock; the coordinator supplies `now` and performs the effects.
public enum FocusEngine {
    public static func handle(_ event: FocusEvent, session: FocusSession?, at now: Date) throws -> FocusTransition {
        switch event {
        case .start(let request):
            let started = FocusSession(
                id: request.id, taskID: request.taskID, action: request.action, mode: request.mode,
                startedAt: now, plannedEnd: now.addingTimeInterval(request.duration), phase: .running
            )
            return changed(to: started)
        case .pause:
            guard var session else { fatalError("not yet") }
            session.phase = .paused(since: now)
            return changed(to: session)
        case .resume:
            guard var session else { fatalError("not yet") }
            session.phase = .running
            return changed(to: session)
        case .startBreak(let duration):
            guard var session else { fatalError("not yet") }
            session.phase = .onBreak(until: now.addingTimeInterval(duration))
            return changed(to: session)
        case .complete:
            guard var session else { fatalError("not yet") }
            session.phase = .ended(at: now, reason: .completed)
            return changed(to: session)
        default:
            fatalError("not yet")
        }
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
