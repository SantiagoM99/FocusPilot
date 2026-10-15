/// Why the engine refused an event. The session is left as it was.
public enum FocusEngineError: Error, Equatable {
    case noActiveSession
    case sessionAlreadyActive
    case nonPositiveDuration
    case notAllowed(FocusEvent, in: SessionPhase)
}
