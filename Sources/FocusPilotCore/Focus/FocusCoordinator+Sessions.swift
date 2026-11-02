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
        try await repository.forgetEndedExceptions()
        if policy == nil {
            try await publish(repository.republish())
        }
        try await followNow()
    }

    /// Starts a session on all projects, or on the chosen `projects` (#56,
    /// decision 0004). Nothing needs to be in Now; the task that is, if any,
    /// is the first one the session touches.
    public func startSession(duration: TimeInterval, mode: SessionMode, projects: [Int64] = []) async throws {
        let scope = try await scope(of: projects)
        let task = try await repository.nowTask()
        let request = SessionRequest(id: UUID(), taskID: task?.id, action: task?.title, mode: mode, duration: duration,
                                     scope: scope)
        let touched = task.map { PilotEvent(kind: .taskTouched, at: now(), sessionID: request.id, taskID: $0.id) }
        try await handle(.start(request), events: touched.map { [$0] } ?? [])
    }

    /// The chosen projects as they are listed, with their titles.
    private func scope(of projects: [Int64]) async throws -> SessionScope {
        guard !projects.isEmpty else { return .allProjects }
        let listed = try await repository.projects().compactMap { project in
            project.id.map { ScopedProject(id: $0, title: project.title) }
        }
        guard Set(projects).isSubset(of: listed.map(\.id)) else { throw SessionError.unknownProject }
        return SessionScope(projects: listed.filter { projects.contains($0.id) })
    }

    /// Keeps the active session on the task in Now, which the owner may
    /// change at any time without ending the session. Each new task is
    /// recorded, and the policy is published again so blocked pages name it.
    /// Strict waits and exceptions are untouched (decision 0003).
    func followNow() async throws {
        guard var active = session, !active.hasEnded else { return }
        let task = try await repository.nowTask()
        guard task?.id != active.taskID else { return }
        active.follow(now: task.map { ($0.id, $0.title) })
        let change = try await repository.recordNowChange(active, at: now())
        session = active
        await publish(change)
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
        try await repository.forgetEndedExceptions()
    }

    /// Completes the session. A strict session ending before its planned end
    /// first needs the owner's confirmation, then waits `StrictEarlyEnd.wait`
    /// from that confirmation on the monotonic clock; until then it keeps
    /// running.
    public func complete(confirmed: Bool = false) async throws -> SessionCompletion {
        if let active = session, !active.hasEnded, active.mode == .strict, now() < active.plannedEnd {
            if earlyEnd?.request != active.id {
                guard confirmed else { return .needsConfirmation }
                earlyEnd = StrictWait(request: active.id, confirmedAt: uptime())
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
        earlyEnd.map(availableAt)
    }

    /// When a strict wait is over, on the wall clock for display.
    func availableAt<Request>(_ wait: StrictWait<Request>) -> Date {
        now().addingTimeInterval(wait.remaining(at: uptime()) / .seconds(1))
    }

    /// The owner changed their mind about ending a strict session early.
    public func cancelEarlyEnd() async {
        earlyEnd = nil
        await broadcast()
    }

    /// One engine step: record the session and revisions in one write, then
    /// publish the wrapped policies and deliver notices.
    private func handle(_ event: FocusEvent, events: [PilotEvent] = []) async throws {
        let at = now()
        let transition = try FocusEngine.handle(event, session: session, at: at)
        // Starting a strict session cancels exceptions granted before it,
        // for apps and sites (decision 0003, 2026-10-22).
        var cancelsExceptions = false
        if case .start(let request) = event, request.mode == .strict { cancelsExceptions = true }
        let recorded = try await repository.record(transition, cancellingExceptionsAt: cancelsExceptions ? at : nil,
                                                   events: events)
        var revisions = recorded.revisions.makeIterator()
        session = transition.session
        if session?.hasEnded != false {
            earlyEnd = nil
            ruleWait = nil
            exceptionWait = nil
            exceptionWaitReason = nil
        }
        for effect in transition.effects {
            switch effect {
            case .persist:
                break
            case .publishPolicy(let sessionPolicy):
                await publish(revision: revisions.next()!, inputs: recorded.inputs, session: sessionPolicy, at: at)
            case .notify(let notice):
                await notices.deliver(notice)
            }
        }
        await broadcast()
    }
}
