import AppKit
import FocusPilotCore

/// Hides blocked Mac apps while FocusPilot runs (decision 0003, 2026-10-14).
///
/// It only reports which app launched or came to the front and carries out
/// `AppBlocking.verdict`: it hides the app with `NSRunningApplication.hide()`
/// and shows the blocked-app panel. It never quits an app, never sends
/// keystrokes and needs no Accessibility permission. It checks the front app
/// again whenever the policy changes and at `AppBlocking.nextChange`, so an
/// exception that runs out while its app is in front is applied on time.
@MainActor
@Observable
final class AppBlocker {
    @ObservationIgnored private unowned let model: AppModel
    @ObservationIgnored private lazy var panel = BlockedAppPanelController(model: model, blocker: self)
    /// The last app the owner had in front that was not hidden; Return to task goes back to it.
    @ObservationIgnored private var lastAllowedFront: NSRunningApplication?
    @ObservationIgnored private var recheck: Task<Void, Never>?
    /// The session last seen, to notice one starting.
    @ObservationIgnored private var sessionID: UUID?
    /// Whether it watches app launches; only then are apps protected.
    /// Observed, so the Apps line updates when it starts.
    private(set) var isRunning = false

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let center = NSWorkspace.shared.notificationCenter
        Task { [weak self] in
            for await note in center.notifications(named: NSWorkspace.didActivateApplicationNotification) {
                self?.evaluate(Self.app(in: note), ownerSwitched: true)
            }
        }
        // Launches that do not come to the front, so the app is hidden
        // before the owner sees it. The system skips background apps.
        Task { [weak self] in
            for await note in center.notifications(named: NSWorkspace.didLaunchApplicationNotification) {
                self?.evaluate(Self.app(in: note), ownerSwitched: false)
            }
        }
        policyChanged()
    }

    /// The policy or session changed: the front app may now be blocked.
    /// This only hides; it is not the owner switching apps, so it neither
    /// closes the panel nor changes where Return to task goes.
    func policyChanged() {
        guard isRunning else { return }
        let active = model.snapshot.activeSession?.id
        if let active, active != sessionID { hideRunningBlockedApps() }
        sessionID = active
        evaluate(NSWorkspace.shared.frontmostApplication, ownerSwitched: false)
        recheck?.cancel()
        guard let next = AppBlocking.nextChange(in: model.snapshot.policy, after: .now) else { return }
        recheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow) + 0.05))
            guard !Task.isCancelled else { return }
            self?.policyChanged()
        }
    }

    /// `ownerSwitched` is true only for an activation notification: the
    /// owner (or the system, right after a hide) brought `app` forward.
    private func evaluate(_ app: NSRunningApplication?, ownerSwitched: Bool) {
        guard let app, let bundleID = app.bundleIdentifier, app != NSRunningApplication.current else { return }
        let verdict = AppBlocking.verdict(for: bundleID, policy: model.snapshot.policy,
                                          ownBundleID: Bundle.main.bundleIdentifier, at: .now)
        guard case .hide(let reason) = verdict else {
            if ownerSwitched {
                lastAllowedFront = app
                panel.ownerActivated(app)
            }
            return
        }
        // An app allowed a moment ago (its schedule opened, its exception
        // ran out) is no longer somewhere to return to.
        if lastAllowedFront == app { lastAllowedFront = nil }
        if ownerSwitched { model.noteBlockedApp(bundleID) }
        hide(app)
        panel.show(BlockedApp(app: app, reason: reason))
    }

    /// A session just started: hide every blocked app already open, not
    /// only the one in front, which `evaluate` then shows the panel for.
    private func hideRunningBlockedApps() {
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isHidden && $0 != NSRunningApplication.current
        }
        let toHide = Set(AppBlocking.appsToHide(running: running.compactMap(\.bundleIdentifier), policy: model.snapshot.policy,
                                                ownBundleID: Bundle.main.bundleIdentifier, at: .now))
        for app in running where toHide.contains(app.bundleIdentifier ?? "") && !app.isActive {
            if lastAllowedFront == app { lastAllowedFront = nil }
            hide(app)
        }
    }

    /// `hide()` can report false while the hide is still on its way, and an
    /// app that is still launching may ignore it, so ask again for about a
    /// second until the app reports hidden.
    private func hide(_ app: NSRunningApplication) {
        Task {
            for _ in 0..<10 {
                guard !app.isTerminated else { return }
                _ = app.hide()
                try? await Task.sleep(for: .milliseconds(100))
                if app.isHidden { return }
            }
        }
    }

    /// Return to task: the app in front before the blocked one, or the
    /// planning window if there was none.
    func returnToTask() {
        panel.close()
        guard let target = lastAllowedFront, !target.isTerminated else {
            model.planningWindowRequests += 1
            return
        }
        Self.bringForward(target)
    }

    /// An exception was granted: show the app the owner asked for.
    func showExcepted(_ app: NSRunningApplication) {
        panel.close()
        app.unhide()
        Self.bringForward(app)
    }

    /// Cooperative activation (macOS 14 and later): FocusPilot yields to
    /// the target and asks it to come forward on FocusPilot's behalf. The
    /// panel never activates FocusPilot, so the system may refuse; then
    /// LaunchServices opens the running app, as the Dock would.
    private static func bringForward(_ app: NSRunningApplication) {
        NSApplication.shared.yieldActivation(to: app)
        _ = app.activate(from: .current, options: [])
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !app.isActive, !app.isTerminated, let url = app.bundleURL else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
    }

    private static func app(in note: Notification) -> NSRunningApplication? {
        note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }
}

/// A hidden app and the rule that hid it, as the panel shows them.
struct BlockedApp: Equatable {
    let app: NSRunningApplication
    let reason: AppBlockReason

    var bundleID: String { app.bundleIdentifier ?? "" }
    var name: String { app.localizedName ?? bundleID }
}
