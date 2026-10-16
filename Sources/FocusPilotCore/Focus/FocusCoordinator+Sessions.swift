import Foundation

/// Focus sessions: the coordinator feeds owner commands and the passing of
/// time to `FocusEngine` and performs the effects it returns, in order.
extension FocusCoordinator {
    /// Loads the last session and reconciles it with the clock, so a session
    /// that ended while the app was quit is recorded at its planned end and
    /// the extensions get a fresh policy.
    public func launch() async throws {
        session = try await repository.latestSession()
        try await handle(.reconcile)
    }

    /// Starts a session on the pinned Now task.
    public func startSession(duration: TimeInterval, mode: SessionMode) async throws {
        guard let task = try await repository.nowTask() else { throw SessionError.noCurrentTask }
        try await handle(.start(SessionRequest(id: UUID(), taskID: task.id, action: task.title, mode: mode, duration: duration)))
    }

    public func pause() async throws {
        try await handle(.pause)
    }

    public func resume() async throws {
        try await handle(.resume)
    }

    /// Applies any deadline the clock has passed. Called at `nextDeadline`,
    /// after the Mac wakes, and at launch.
    public func reconcile() async throws {
        try await handle(.reconcile)
    }

    /// Completes the session. A strict session ending before its planned end
    /// first needs the owner's confirmation, then waits `StrictEarlyEnd.wait`
    /// from that confirmation on the monotonic clock; until then it keeps
    /// running.
    public func complete(confirmed: Bool = false) async throws -> SessionCompletion {
        if let active = session, !active.hasEnded, active.mode == .strict, now() < active.plannedEnd {
            if earlyEndRequestedAt == nil {
                guard confirmed else { return .needsConfirmation }
                earlyEndRequestedAt = uptime()
                await broadcast()
            }
            if let availableAt = earlyEndAvailableAt(), now() < availableAt { return .waitUntil(availableAt) }
        }
        try await handle(.complete)
        return .completed
    }

    /// When the confirmed early end may complete, measured on `uptime` and
    /// shown on the wall clock; `nil` when the owner has not confirmed.
    func earlyEndAvailableAt() -> Date? {
        guard let requested = earlyEndRequestedAt else { return nil }
        let remaining = requested + .seconds(StrictEarlyEnd.wait) - uptime()
        return now().addingTimeInterval(max(0, remaining / .seconds(1)))
    }

    /// The owner changed their mind about ending a strict session early.
    public func cancelEarlyEnd() async {
        earlyEndRequestedAt = nil
        await broadcast()
    }

    /// One engine step: record the session and revisions in one write, then
    /// publish the wrapped policies and deliver notices.
    private func handle(_ event: FocusEvent) async throws {
        let at = now()
        let transition = try FocusEngine.handle(event, session: session, at: at)
        var revisions = try await repository.record(transition).makeIterator()
        session = transition.session
        if session?.hasEnded != false {
            earlyEndRequestedAt = nil
        }
        for effect in transition.effects {
            switch effect {
            case .persist:
                break
            case .publishPolicy(let policy):
                await publisher.publish(PublishedPolicy(revision: revisions.next()!, effectiveAt: at, session: policy))
            case .notify(let notice):
                await notices.deliver(notice)
            }
        }
        await broadcast()
    }
}
