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
            return FocusTransition(session: started, effects: [.persist(started), .publishPolicy(policy(for: started))])
        default:
            fatalError("not yet")
        }
    }

    static func policy(for session: FocusSession) -> SessionPolicy? {
        SessionPolicy(sessionID: session.id, mode: session.mode, end: session.plannedEnd)
    }
}
