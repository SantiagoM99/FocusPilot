import Foundation

/// Timed exceptions (DATA_AND_MEMORY, Exception) for an app, a site or one
/// page (#14). A grant is stored and published in the same write, with an
/// absolute expiry measured from the grant. Sites and pages must be blocked
/// by a rule; a request for something an exception already allows returns
/// that exception's expiry and grants nothing, so every Chrome profile and
/// the app share one deadline.
///
/// During a strict session a request first returns `needsConfirmation`,
/// then waits `StrictEarlyEnd.wait` from the confirmation on the monotonic
/// clock, like ending early (design 05 and 10; the 60-second wait for
/// exceptions is a proposed value awaiting owner confirmation). It also
/// needs a reason. Outside a strict session the grant is immediate.
extension FocusCoordinator {
    public func requestException(_ scope: ExceptionScope, duration: TimeInterval, reason: String? = nil,
                                 confirmed: Bool = false) async throws -> ExceptionOutcome {
        guard TimedException.durations.contains(duration) else { throw ExceptionError.unsupportedDuration }
        let scope = try scope.normalized()
        // Already allowed (say, from another Chrome profile): its expiry
        // stands and a strict session asks nothing.
        if let expiry = try await repository.coveringExpiry(of: scope, at: now()) { return .granted(expiresAt: expiry) }
        let typed = reason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard let active = session, !active.hasEnded, active.mode == .strict else {
            return try await grant(scope, duration: duration, reason: typed)
        }
        let request = ExceptionRequest(scope: scope, duration: duration)
        if let wait = exceptionWait, wait.hasExpired(at: uptime()) || wait.request != request {
            exceptionWait = nil
            exceptionWaitReason = nil
        }
        guard let reason = typed ?? exceptionWaitReason else { throw ExceptionError.reasonRequired }
        guard let wait = exceptionWait else {
            guard confirmed else { return .needsConfirmation }
            let wait = StrictWait(request: request, confirmedAt: uptime())
            exceptionWait = wait
            exceptionWaitReason = reason
            await broadcast()
            return .waitUntil(availableAt(wait))
        }
        if wait.remaining(at: uptime()) > .zero { return .waitUntil(availableAt(wait)) }
        exceptionWait = nil
        exceptionWaitReason = nil
        return try await grant(scope, duration: duration, reason: reason)
    }

    /// The owner changed their mind about a strict-session exception.
    public func cancelException() async {
        exceptionWait = nil
        exceptionWaitReason = nil
        await broadcast()
    }

    func pendingException() -> PendingException? {
        guard let wait = exceptionWait, !wait.hasExpired(at: uptime()) else { return nil }
        return PendingException(scope: wait.request.scope, duration: wait.request.duration, availableAt: availableAt(wait),
                                reason: exceptionWaitReason)
    }

    private func grant(_ scope: ExceptionScope, duration: TimeInterval, reason: String?) async throws -> ExceptionOutcome {
        let at = now()
        let activeSession = session.flatMap { $0.hasEnded ? nil : $0 }
        let exception = TimedException(scope: scope, grantedAt: at, expiresAt: at.addingTimeInterval(duration),
                                       sessionID: activeSession?.id, reason: reason)
        switch try await repository.grant(exception) {
        case .granted(let change):
            await publish(change)
            return .granted(expiresAt: exception.expiresAt)
        case .alreadyCovered(let expiry):
            return .granted(expiresAt: expiry)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
