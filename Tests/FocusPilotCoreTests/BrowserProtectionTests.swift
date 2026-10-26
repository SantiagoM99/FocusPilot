import Foundation
import Testing
@testable import FocusPilotCore

private let profileA = "4F5CE721-0000-4000-8000-00000000000A"
private let profileB = "4F5CE721-0000-4000-8000-00000000000B"

private func profile(_ id: String = profileA, _ state: ChromeProfileStatus.State = .acknowledged(revision: 9),
                     incognito: Bool = true, allSites: Bool = true) -> ChromeProfileStatus {
    ChromeProfileStatus(profileID: id, state: state, incognitoAllowed: incognito, allSitesAccess: allSites, missingObservations: 0)
}

private func profile(_ state: ChromeProfileStatus.State) -> ChromeProfileStatus {
    profile(profileA, state)
}

private func status(_ profiles: [ChromeProfileStatus] = [profile()], chromeRunning: Bool = true, confirmed: Bool = true,
                    inSession: Bool = false, front: FrontBrowser? = nil) -> BrowserProtection {
    BrowserProtection(profiles: profiles, chromeRunning: chromeRunning, confirmedSinceStart: confirmed,
                      inSession: inSession, front: front)
}

@Suite("Browser protection status")
struct BrowserProtectionTests {
    @Test func everyProfileAcknowledgedWithFullAccessIsProtected() {
        let s = status([profile(), profile(profileB)])

        #expect(s.level == .protected)
        #expect(s.line == "Chrome protected")
        #expect(s.footer == "Chrome · Protected")
        #expect(s.detail == "All 2 Chrome profiles have your latest rules")
    }

    // Decision 0003, 2026-10-22.
    @Test func incognitoOffIsNeverFullProtection() {
        let s = status([profile(), profile(profileB, incognito: false)])

        #expect(s.level == .degraded)
        #expect(s.line == "Chrome protected · Incognito unprotected")
        #expect(s.footer == "Chrome · Incognito unprotected")
        #expect(s.detail == "Turn on Allow in Incognito for the FocusPilot extension in chrome://extensions")
    }

    @Test func noExtensionIsDegraded() {
        let s = status([])

        #expect(s.level == .degraded)
        #expect(s.line == "Chrome extension not connected")
        #expect(s.footer == "Chrome · Not connected")
    }

    @Test func limitedSiteAccessIsDegraded() {
        let s = status([profile(allSites: false)])

        #expect(s.level == .degraded)
        #expect(s.line == "Chrome extension needs site access")
        #expect(s.footer == "Chrome · Permission missing")
    }

    // With Chrome open, a disconnected profile may have the extension turned off.
    @Test func aDisconnectedProfileWhileChromeRunsIsDegraded() {
        let s = status([profile(), profile(profileB, .disconnected(lastSeen: nil))])

        #expect(s.level == .degraded)
        #expect(s.line == "Chrome protected · 1 profile disconnected")
        #expect(s.footer == "Chrome · Disconnected")
        #expect(s.detail == "A profile's extension isn't connected. Forget it in Settings if you no longer use it.")
    }

    @Test func aProfileStillApplyingThePolicyIsSyncing() {
        for state in [ChromeProfileStatus.State.waiting, .syncing(acknowledged: 8)] {
            let s = status([profile(), profile(profileB, state)])

            #expect(s.level == .syncing)
            #expect(s.line == "Chrome is updating…")
            #expect(s.footer == "Chrome · Updating…")
        }
    }

    @Test func withChromeClosedNothingIsConfirmed() {
        let s = status([profile(.disconnected(lastSeen: nil))], chromeRunning: false)

        #expect(s.level == .unknown)
        #expect(s.line == "Chrome not running")
        #expect(s.detail == "It gets the current policy when it opens")
    }

    @Test func afterARestartOrWakeTheStatusIsUnknownUntilConfirmed() {
        let s = status(confirmed: false)

        #expect(s.level == .unknown)
        #expect(s.line == "Chrome not confirmed yet")
        #expect(s.footer == "Chrome · Unknown")
    }

    // Review of #48: an extension turned off never acknowledges, so waiting
    // for confirmation would say "not confirmed yet" forever.
    @Test func afterARestartOrWakeAnExtensionTurnedOffIsDegradedNotUnknown() {
        let s = status([profile(.disconnected(lastSeen: nil))], confirmed: false)

        #expect(s.level == .degraded)
        #expect(s.line == "Chrome extension not connected")
        #expect(s.footer == "Chrome · Disconnected")
    }

    // Safari is unverified, so the footer names Chrome, not "Browsers".
    @Test func theFooterNamesChromeAlone() {
        #expect(status().footer.hasPrefix("Chrome · "))
        #expect(status(chromeRunning: false).footer == "Chrome · Unknown")
    }

    @Test func anUnsupportedBrowserInFrontDuringASessionIsDegraded() {
        let s = status(inSession: true, front: .unsupported(name: "Firefox"))

        #expect(s.level == .degraded)
        #expect(s.line == "Firefox in front · not protected")
        #expect(s.footer == "Firefox · not protected")
        #expect(s.detail == "Chrome rules still apply; Firefox has no FocusPilot extension")
    }

    @Test func anUnsupportedBrowserOutsideASessionChangesNothing() {
        #expect(status(front: .unsupported(name: "Firefox")).level == .protected)
    }

    @Test func chromeInFrontWithAProfileNotYetProtectedDuringASessionIsDegraded() {
        let s = status([profile(.waiting)], inSession: true, front: .chrome)

        #expect(s.level == .degraded)
        #expect(s.line == "Chrome in front · not yet protected")
    }

    // Decision 0003, 2026-10-20: Safari relies on the owner's own blocker.
    @Test func safariIsAnExternalBlockerThatIsNeverVerified() {
        #expect(status().safari == "Safari · external blocker, not verified")
        #expect(status(inSession: true, front: .safari).level == .protected)
    }

    @Test func browsersAreRecognizedByBundleID() {
        #expect(FrontBrowser("com.google.Chrome", name: "Google Chrome") == .chrome)
        #expect(FrontBrowser("com.apple.Safari", name: "Safari") == .safari)
        #expect(FrontBrowser("org.mozilla.firefox", name: "Firefox") == .unsupported(name: "Firefox"))
        #expect(FrontBrowser("company.thebrowser.Browser", name: "Arc") == .unsupported(name: "Arc"))
        #expect(FrontBrowser("com.google.Chrome.canary", name: "Google Chrome Canary") == .unsupported(name: "Google Chrome Canary"))
        #expect(FrontBrowser("com.apple.dt.Xcode", name: "Xcode") == nil)
    }
}

@Suite("Browser protection evidence")
struct ProtectionEvidenceTests {
    @Test func atLaunchNothingIsConfirmed() {
        #expect(!ProtectionEvidence().isConfirmed)
    }

    @Test func everyConnectedProfileAcknowledgingConfirmsIt() {
        var evidence = ProtectionEvidence()

        evidence.update([profile(), profile(profileB, .disconnected(lastSeen: nil))])

        #expect(evidence.isConfirmed)
    }

    @Test func aProfileStillWaitingKeepsItUnconfirmed() {
        var evidence = ProtectionEvidence()

        evidence.update([profile(), profile(profileB, .waiting)])
        evidence.update([])

        #expect(!evidence.isConfirmed)
    }

    // The app republishes on wake; only an acknowledgement of that newer
    // revision is evidence again.
    @Test func afterWakeOnlyANewerAcknowledgementConfirms() {
        var evidence = ProtectionEvidence()
        evidence.update([profile(.acknowledged(revision: 9))])

        evidence.markStale(currentRevision: 9)
        evidence.update([profile(.acknowledged(revision: 9))])
        #expect(!evidence.isConfirmed)

        evidence.update([profile(.acknowledged(revision: 10))])
        #expect(evidence.isConfirmed)
    }

    @Test func confirmedStaysConfirmedUntilMarkedStale() {
        var evidence = ProtectionEvidence()
        evidence.update([profile()])

        evidence.update([profile(.syncing(acknowledged: 9))])

        #expect(evidence.isConfirmed)
    }
}

/// #17: the Apps fact depends on app blocking actually running.
@Suite("Apps protection status")
struct AppProtectionStatusTests {
    private let now = wednesdayMorningInBogota
    private let rules = [BlockRuleSet(targets: [.app(bundleID: "com.burbn.instagram", name: "Instagram")], activation: .always)]

    private func line(running: Bool) -> AppProtectionText {
        let compiled = PolicyCompiler.compile(rules: rules, allowed: [], session: nil, exceptions: [])
        return AppProtectionText(rules: rules, policy: CompiledPolicy(revision: 1, effectiveAt: now, rules: compiled), at: now,
                                 isRunning: running)
    }

    @Test func hidingAppsIsProtectedWhileRunning() {
        #expect(line(running: true).isProtected)
        #expect(line(running: true).short == "Apps · protected while running")
    }

    @Test func appBlockingThatIsNotRunningProtectsNothing() {
        let text = line(running: false)

        #expect(!text.isProtected)
        #expect(text.summary == "Apps not protected · Instagram")
        #expect(text.detail == "App blocking isn't running")
        #expect(text.short == "Apps · not protected")
    }

    @Test func withNothingToHideTheShortLineSaysSo() {
        let text = AppProtectionText(rules: [], policy: nil, at: now, isRunning: true)

        #expect(!text.isProtected)
        #expect(text.short == "Apps · none hidden now")
    }
}
