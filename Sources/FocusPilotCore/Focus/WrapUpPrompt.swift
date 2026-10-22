import Foundation

/// Asks the owner for a wrap-up when the session they are watching ends
/// (#20). Pauses never ask (owner decision, 2026-10-17).
public struct WrapUpPrompt: Equatable, Sendable, Identifiable {
    public var session: FocusSession

    public init(session: FocusSession) {
        self.session = session
    }

    /// One per session, so a sheet shown again for the same session keeps
    /// what the owner typed.
    public var id: UUID {
        session.id
    }

    /// The prompt for a change from `previous` to `current`, or nil.
    ///
    /// Only an end the app saw counts: a session that ended while the app
    /// was quit (no `previous`) asks nothing, nor do starting, pausing,
    /// resuming, breaks or a different session.
    public static func after(_ previous: FocusSession?, _ current: FocusSession?) -> WrapUpPrompt? {
        guard let previous, let current, previous.id == current.id, !previous.hasEnded, current.hasEnded else {
            return nil
        }
        return WrapUpPrompt(session: current)
    }

    public var title: String {
        "Session ended"
    }

    /// The task and how long the session lasted, e.g. "Explain baseline results · 50 min".
    public var detail: String {
        let end: Date = if case .ended(let at, _) = session.phase { at } else { session.startedAt }
        let minutes = Int((end.timeIntervalSince(session.startedAt) / 60).rounded())
        return "\(session.action) · \(minutes) min"
    }
}
