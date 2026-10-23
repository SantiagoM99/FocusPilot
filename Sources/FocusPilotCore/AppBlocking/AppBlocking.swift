import Foundation

/// Why a Mac app is hidden.
public enum AppBlockReason: Equatable, Sendable {
    /// Session rules apply (a strict session's also through pauses and breaks).
    case session(SessionBlock)
    case always
    /// One of the schedule's windows is open.
    case schedule(WeeklySchedule)
}

/// What to do with a Mac app that came to the front or launched.
public enum AppVerdict: Equatable, Sendable {
    case allow
    case hide(AppBlockReason)
}

/// Whether a Mac app is hidden (decision 0003, 2026-10-14): a pure function
/// of the compiled policy and the instant, so the AppKit side only reports
/// which app came forward and carries out the verdict.
public enum AppBlocking {
    /// Hidden by no rule: hiding Finder leaves the owner without a desktop.
    static let neverHidden: Set<String> = ["com.apple.finder"]

    /// `ownBundleID` is FocusPilot's, which is never hidden either. Bundle
    /// IDs compare without case, as rule targets do.
    public static func verdict(for bundleID: String, policy: CompiledPolicy?, ownBundleID: String? = nil,
                               at now: Date) -> AppVerdict {
        let id = bundleID.lowercased()
        guard let policy, !neverHidden.contains(id), id != ownBundleID?.lowercased(),
              !contains(policy.allowed.apps, id) else { return .allow }
        if policy.exceptions.contains(where: { $0.exempts(app: id, at: now) }) { return .allow }
        if let session = policy.session, contains(session.targets.apps, id), sessionRulesApply(session, at: now) {
            return .hide(.session(session))
        }
        if contains(policy.always.apps, id) { return .hide(.always) }
        if let block = policy.scheduled.first(where: { contains($0.targets.apps, id) && $0.schedule.contains(now) }) {
            return .hide(.schedule(block.schedule))
        }
        return .allow
    }

    /// Of the running apps' bundle IDs, in order, those to hide now: used
    /// when a session starts, so apps already open are hidden too, not
    /// only the one in front.
    public static func appsToHide(running: [String], policy: CompiledPolicy?, ownBundleID: String? = nil,
                                  at now: Date) -> [String] {
        running.filter { verdict(for: $0, policy: policy, ownBundleID: ownBundleID, at: now) != .allow }
    }

    /// The first instant after `now` at which a verdict may change on its
    /// own: an app exception expiring, a normal break ending, a normal
    /// session reaching its planned end, or a schedule naming apps opening
    /// or closing. The app checks the front app again then. A strict
    /// session's end waits for the coordinator, which publishes a new policy.
    public static func nextChange(in policy: CompiledPolicy?, after now: Date) -> Date? {
        guard let policy else { return nil }
        var instants = policy.exceptions.compactMap { exception -> Date? in
            if case .app = exception.scope { exception.expiresAt } else { nil }
        }
        if let session = policy.session, !session.targets.apps.isEmpty {
            instants += [session.resumesAt, session.mode == .normal ? session.end : nil].compactMap { $0 }
        }
        instants += policy.scheduled.filter { !$0.targets.apps.isEmpty }.compactMap { $0.schedule.nextChange(after: now) }
        return instants.filter { $0 > now }.min()
    }

    /// As the extensions judge it without the app: a normal session's
    /// rules lift during a break until `resumesAt` and stop at the planned
    /// end; a strict one's continue past it until the app ends the session.
    static func sessionRulesApply(_ session: SessionBlock, at now: Date) -> Bool {
        if let resumesAt = session.resumesAt, now < resumesAt { return false }
        return session.mode == .strict || now < session.end
    }

    private static func contains(_ apps: [String], _ id: String) -> Bool {
        apps.contains { $0.lowercased() == id }
    }
}

extension PolicyException {
    /// Whether this exception covers the app (a lowercased bundle ID) at `now`.
    func exempts(app id: String, at now: Date) -> Bool {
        guard case .app(let bundleID) = scope else { return false }
        return bundleID.lowercased() == id && now < expiresAt
    }
}
