import AppKit
import FocusPilotCore

/// Focus sessions as the views use them. The coordinator does the work; this
/// keeps the latest snapshot, reconciles at the next deadline and on wake,
/// and shows or hides the focus panel.
extension AppModel {
    /// The task a new session would run on: the pinned Now task.
    var nowTask: TodayItem? {
        today.first { $0.status == .now }
    }

    /// Restores a session left running by the last launch, then follows
    /// every snapshot the coordinator streams.
    func followSessions() {
        guard let coordinator else { return }
        Task { [weak self] in
            do {
                try await coordinator.launch()
            } catch {
                self?.sessionError = "Could not restore the session: \(error.localizedDescription)"
            }
            for await snapshot in await coordinator.snapshots() {
                guard let self else { return }
                show(snapshot)
                scheduleReconcile(at: snapshot.nextDeadline)
                focusPanel.update()
            }
        }
        Task { [weak self] in
            for await _ in NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.didWakeNotification) {
                await self?.run { try await $0.reconcile() }
            }
        }
    }

    func requestStartFocus() {
        isStartingFocus = true
    }

    func startSession(minutes: Int, mode: SessionMode) async -> Bool {
        await run { try await $0.startSession(duration: TimeInterval(minutes * 60), mode: mode) }
    }

    func pause() async {
        ownerEndedOrPausedAt = .now
        await run { try await $0.pause() }
    }

    func resume() async {
        await run { try await $0.resume() }
    }

    /// Completes the session. A strict session ending early shows the
    /// confirmation instead; once `confirmed`, it starts the wait, which the
    /// snapshot shows. Returns true when the confirmation is now showing.
    @discardableResult
    func complete(confirmed: Bool = false) async -> Bool {
        var completion: SessionCompletion?
        ownerEndedOrPausedAt = .now
        await run { completion = try await $0.complete(confirmed: confirmed) }
        isConfirmingEarlyEnd = completion == .needsConfirmation
        return isConfirmingEarlyEnd
    }

    func cancelEarlyEnd() async {
        isConfirmingEarlyEnd = false
        await coordinator?.cancelEarlyEnd()
    }

    @discardableResult
    private func run(_ command: (FocusCoordinator) async throws -> Void) async -> Bool {
        guard let coordinator else { return false }
        do {
            try await command(coordinator)
            sessionError = nil
            return true
        } catch {
            sessionError = "Could not update the session: \(error.localizedDescription)"
            return false
        }
    }

    private func scheduleReconcile(at deadline: Date?) {
        reconcileTask?.cancel()
        guard let deadline else { return }
        reconcileTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            await self?.run { try await $0.reconcile() }
        }
    }
}
