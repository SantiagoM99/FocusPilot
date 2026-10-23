import AppKit
import FocusPilotCore

/// Protection status (#17): Browsers from Chrome's per-profile
/// acknowledgements and the browser in front; Apps from `AppBlocker`.
extension AppModel {
    var browserProtection: BrowserProtection {
        BrowserProtection(profiles: chromeProfiles, chromeRunning: chromeRunning,
                          confirmedSinceStart: protectionEvidence.isConfirmed,
                          inSession: snapshot.activeSession != nil, front: frontBrowser)
    }

    /// After a wake, what Chrome acknowledged earlier is no evidence.
    func markProtectionStale() {
        protectionEvidence.markStale(currentRevision: snapshot.policy?.revision)
    }

    /// Follows the owner's front app. FocusPilot itself coming forward (e.g.
    /// to open the menu bar popover) keeps the browser that was in front.
    func followFrontBrowser() {
        noteFront(NSWorkspace.shared.frontmostApplication)
        let center = NSWorkspace.shared.notificationCenter
        Task { [weak self] in
            for await note in center.notifications(named: NSWorkspace.didActivateApplicationNotification) {
                self?.noteFront(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            }
        }
    }

    private func noteFront(_ app: NSRunningApplication?) {
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let browser = app.bundleIdentifier.flatMap { FrontBrowser($0, name: app.localizedName ?? $0) }
        if browser != frontBrowser { frontBrowser = browser }
    }
}
