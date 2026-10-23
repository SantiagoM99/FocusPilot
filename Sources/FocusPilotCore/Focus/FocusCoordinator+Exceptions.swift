import Foundation

/// Timed exceptions (DATA_AND_MEMORY, Exception): an app now, sites and
/// pages with #14. A grant is stored and published in the same write, with
/// an absolute expiry measured from the grant.
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
        let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard let active = session, !active.hasEnded, active.mode == .strict else {
            return try await grant(scope, duration: duration, reason: reason)
        }
        guard reason != nil else { throw ExceptionError.reasonRequired }
        let request = ExceptionRequest(scope: scope, duration: duration)
        if let wait = exceptionWait, wait.hasExpired(at: uptime()) || wait.request != request {
            exceptionWait = nil
        }
        guard let wait = exceptionWait else {
            guard confirmed else { return .needsConfirmation }
            let wait = StrictWait(request: request, confirmedAt: uptime())
            exceptionWait = wait
            await broadcast()
            return .waitUntil(availableAt(wait))
        }
        if wait.remaining(at: uptime()) > .zero { return .waitUntil(availableAt(wait)) }
        exceptionWait = nil
        return try await grant(scope, duration: duration, reason: reason)
    }

    /// The owner changed their mind about a strict-session exception.
    public func cancelException() async {
        exceptionWait = nil
        await broadcast()
    }

    func pendingException() -> PendingException? {
        guard let wait = exceptionWait, !wait.hasExpired(at: uptime()) else { return nil }
        return PendingException(scope: wait.request.scope, duration: wait.request.duration, availableAt: availableAt(wait))
    }

    private func grant(_ scope: ExceptionScope, duration: TimeInterval, reason: String?) async throws -> ExceptionOutcome {
        let at = now()
        let activeSession = session.flatMap { $0.hasEnded ? nil : $0 }
        let exception = TimedException(scope: scope, grantedAt: at, expiresAt: at.addingTimeInterval(duration),
                                       sessionID: activeSession?.id, reason: reason)
        await publish(try await repository.grant(exception))
        return .granted(expiresAt: exception.expiresAt)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
