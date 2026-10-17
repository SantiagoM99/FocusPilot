import Foundation


/// An immutable picture of FocusCoordinator state for the UI to display.
public struct FocusSnapshot: Equatable, Sendable {
    /// SF Symbol used inside the app where the custom glyph is not drawn yet
    /// (logo design 2d). The menu bar uses `MenuBarGlyph` instead.
    public static let fallbackSymbolName = "scope"

    public var currentTaskTitle: String?
    /// The latest session, which may have ended; `nil` before the first one.
    public var session: FocusSession?
    /// Observe-only mode measures without blocking (P0, ticket T13).
    public var isObserveOnly: Bool
    /// When a strict session the owner asked to end early may be completed;
    /// `nil` when no early end is waiting.
    public var earlyEndAvailableAt: Date?
    /// The last policy published to the extensions.
    public var policy: CompiledPolicy?
    /// A rule change waiting out its strict-session delay.
    public var pendingRuleEdit: PendingRuleEdit?
    /// Higher for later coordinator states; the app keeps the newest.
    public var revision: Int

    public init(currentTaskTitle: String? = nil, session: FocusSession? = nil, isObserveOnly: Bool = false,
                earlyEndAvailableAt: Date? = nil, policy: CompiledPolicy? = nil,
                pendingRuleEdit: PendingRuleEdit? = nil, revision: Int = 0) {
        self.currentTaskTitle = currentTaskTitle
        self.session = session
        self.isObserveOnly = isObserveOnly
        self.earlyEndAvailableAt = earlyEndAvailableAt
        self.policy = policy
        self.pendingRuleEdit = pendingRuleEdit
        self.revision = revision
    }

    /// The session that is still running, paused or on a break.
    public var activeSession: FocusSession? {
        guard let session, !session.hasEnded else { return nil }
        return session
    }

    /// Whether session-only rules block now: while running, and through
    /// pauses and breaks of a strict session.
    public var sessionRulesApply: Bool {
        guard let active = activeSession, let policy = FocusEngine.policy(for: active) else { return false }
        return policy.resumesAt == nil
    }

    /// When the coordinator must next be asked to reconcile, such as the
    /// planned end or the end of a break.
    public var nextDeadline: Date? {
        activeSession?.nextDeadline
    }

    /// The state line shown inside the menu and the planning window.
    public var statusText: String {
        activeSession?.action ?? currentTaskTitle ?? "No current task"
    }
}
