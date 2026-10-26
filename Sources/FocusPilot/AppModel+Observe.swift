import AppKit
import FocusPilotCore

/// Observe-only mode and pilot metrics (#21). The tracker hears which app is
/// in front, Chrome's front-tab domain while observing, and each session;
/// what it produces is stored through the coordinator. Raw activity older
/// than a day is deleted at launch and every hour; events stay.
extension AppModel {
    func setObserveOnly(_ on: Bool) async {
        guard let coordinator else { return }
        do {
            try await coordinator.setObserveOnly(on)
            observeError = nil
        } catch ObserveError.strictSession {
            observeError = "Observe only can be turned on once this strict session ends."
        } catch {
            observeError = "Could not change observe only: \(error.localizedDescription)"
        }
        show(await coordinator.snapshot())
        if !on { store(activityTracker.chromeTab(nil, at: .now)) }
    }

    func loadWeeklySummary() async {
        guard let coordinator else { return }
        let now = Date.now
        let events = (try? await coordinator.pilotEvents(since: now.addingTimeInterval(-WeeklySummary.period))) ?? []
        weeklySummary = WeeklySummary(events: events, now: now)
    }

    func track(_ snapshot: FocusSnapshot) {
        store(activityTracker.session(snapshot.session, at: .now))
    }

    func followActivity(location: StorageLocation) {
        noteFrontApp(NSWorkspace.shared.frontmostApplication)
        let center = NSWorkspace.shared.notificationCenter
        Task { [weak self] in
            for await note in center.notifications(named: NSWorkspace.didActivateApplicationNotification) {
                self?.noteFrontApp(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            }
        }
        // Asleep, locked or switched to another user: nothing is in front.
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            Task { [weak self] in
                for await _ in center.notifications(named: name) { self?.noteFrontApp(nil) }
            }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            Task { [weak self] in
                for await _ in center.notifications(named: name) { self?.noteFrontApp(NSWorkspace.shared.frontmostApplication) }
            }
        }
        let inbox = ChromeActivityInbox(location: location)
        Task { [weak self] in
            while let self {
                // Drained either way, so reports never wait in the file.
                for report in inbox.drain(now: .now) where snapshot.isObserveOnly {
                    store(activityTracker.chromeTab(report.domain, at: report.at))
                }
                // Often, so a short visit is placed before the next app switch.
                try? await Task.sleep(for: .seconds(1))
            }
        }
        Task { [weak self] in
            while let coordinator = self?.coordinator {
                try? await coordinator.pruneRawActivity()
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    private func noteFrontApp(_ app: NSRunningApplication?) {
        store(activityTracker.frontApp(app?.bundleIdentifier, at: .now))
    }

    private func store(_ record: ActivityRecord) {
        guard !record.isEmpty, let coordinator else { return }
        Task { try? await coordinator.record(record) }
    }
}
