import Foundation

/// Asks the owner for a wrap-up when the session they are watching pauses
/// or ends (#20), so the app shows the sheet exactly then.
public struct WrapUpPrompt: Equatable, Sendable, Identifiable {
    public enum Moment: Equatable, Sendable {
        case paused, ended
    }

    public var session: FocusSession
    public var moment: Moment

    public init(session: FocusSession, moment: Moment) {
        self.session = session
        self.moment = moment
    }

    /// One per session and moment, so a sheet for the pause is replaced
    /// when the same session then ends.
    public var id: String {
        "\(session.id.uuidString)-\(moment)"
    }

    /// The prompt for a change from `previous` to `current`, or nil.
    ///
    /// Only a change the app saw counts: a session that ended while the app
    /// was quit (no `previous`) asks nothing, nor do starting, resuming,
    /// breaks or a different session.
    public static func after(_ previous: FocusSession?, _ current: FocusSession?) -> WrapUpPrompt? {
        guard let previous, let current, previous.id == current.id, !previous.hasEnded else { return nil }
        switch (previous.phase, current.phase) {
        case (_, .ended):
            return WrapUpPrompt(session: current, moment: .ended)
        case (.paused, .paused):
            return nil
        case (_, .paused):
            return WrapUpPrompt(session: current, moment: .paused)
        default:
            return nil
        }
    }

    public var title: String {
        switch moment {
        case .paused: "Session paused"
        case .ended: "Session ended"
        }
    }

    /// The task and the session's length so far, e.g. "Explain baseline results · 50 min".
    public var detail: String {
        let until: Date = switch session.phase {
        case .paused(let since): since
        case .ended(let at, _): at
        case .running, .onBreak: session.startedAt
        }
        let minutes = Int((until.timeIntervalSince(session.startedAt) / 60).rounded())
        return "\(session.action) · \(minutes) min"
    }
}
