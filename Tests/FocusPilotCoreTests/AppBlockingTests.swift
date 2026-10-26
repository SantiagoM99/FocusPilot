import Foundation
import Testing
@testable import FocusPilotCore

private let instagram = ActivityTarget.app(bundleID: "com.burbn.instagram", name: "Instagram")
private let instagramID = "com.burbn.instagram"

/// A compiled policy as the coordinator would publish it.
private func policy(_ rules: [BlockRuleSet], allowed: [AllowedActivity] = [], session: SessionPolicy? = nil,
                    exceptions: [PolicyException] = []) -> CompiledPolicy {
    CompiledPolicy(revision: 1, effectiveAt: wednesdayMorningInBogota,
                   rules: PolicyCompiler.compile(rules: rules, allowed: allowed, session: session, exceptions: exceptions))
}

@Suite("Hide or allow a Mac app")
struct AppBlockingTests {
    private let now = wednesdayMorningInBogota

    @Test func anAlwaysBlockedAppIsHidden() {
        let compiled = policy([BlockRuleSet(targets: [instagram], activation: .always)])

        #expect(AppBlocking.verdict(for: instagramID, policy: compiled, at: now) == .hide(.always))
    }

    @Test func anAppInNoRuleIsAllowed() {
        let compiled = policy([BlockRuleSet(targets: [instagram], activation: .always)])

        #expect(AppBlocking.verdict(for: "com.apple.TextEdit", policy: compiled, at: now) == .allow)
        #expect(AppBlocking.verdict(for: instagramID, policy: nil, at: now) == .allow)
    }

    @Test func finderFocusPilotAndAllowedAppsAreNeverHidden() {
        // A policy that names them anyway, as an older or hand-made one could.
        var compiled = policy([BlockRuleSet(targets: [instagram], activation: .always)])
        compiled.always.apps += ["com.apple.finder", "com.focuspilot.app", "org.zotero.zotero"]
        compiled.allowed.apps = ["org.zotero.zotero"]

        for id in ["com.apple.finder", "com.focuspilot.app", "org.zotero.zotero"] {
            #expect(AppBlocking.verdict(for: id, policy: compiled, ownBundleID: "com.focuspilot.app", at: now) == .allow)
        }
    }

    @Test func bundleIDsMatchWhateverTheirCase() {
        let compiled = policy([BlockRuleSet(targets: [.app(bundleID: "com.Burbn.Instagram", name: "Instagram")], activation: .always)])

        #expect(AppBlocking.verdict(for: "com.burbn.instagram", policy: compiled, at: now) == .hide(.always))
        #expect(AppBlocking.verdict(for: "COM.APPLE.FINDER", policy: compiled, at: now) == .allow)
    }

    @Test func aScheduledAppIsHiddenOnlyInsideItsWindows() {
        let workdays = WeeklySchedule(days: [.mon, .tue, .wed, .thu, .fri], from: ClockTime(8, 0), to: ClockTime(18, 0), timeZone: bogota)
        let compiled = policy([BlockRuleSet(targets: [instagram], activation: .schedule(workdays))])

        #expect(AppBlocking.verdict(for: instagramID, policy: compiled, at: now) == .hide(.schedule(workdays)))
        #expect(AppBlocking.verdict(for: instagramID, policy: compiled, at: instant("2026-10-14T18:00:00-05:00")) == .allow)
    }

    @Test func sessionOnlyAppsAreHiddenWhileTheSessionRulesApply() {
        let rules = [BlockRuleSet(targets: [instagram], activation: .sessionOnly)]
        let end = now.addingTimeInterval(25 * 60)
        let running = policy(rules, session: SessionPolicy(sessionID: UUID(), mode: .normal, end: end))
        let block = try! #require(running.session)

        #expect(AppBlocking.verdict(for: instagramID, policy: running, at: now) == .hide(.session(block)))
        #expect(AppBlocking.verdict(for: instagramID, policy: policy(rules), at: now) == .allow)
    }

    @Test func aNormalBreakLiftsSessionRulesUntilItEnds() {
        let breakEnd = now.addingTimeInterval(5 * 60)
        let onBreak = policy([BlockRuleSet(targets: [instagram], activation: .sessionOnly)],
                             session: SessionPolicy(sessionID: UUID(), mode: .normal, end: now.addingTimeInterval(25 * 60), resumesAt: breakEnd))

        #expect(AppBlocking.verdict(for: instagramID, policy: onBreak, at: now) == .allow)
        #expect(AppBlocking.verdict(for: instagramID, policy: onBreak, at: breakEnd) != .allow)
    }

    @Test func aNormalSessionStopsHidingAtItsPlannedEndAStrictOneDoesNot() {
        let end = now.addingTimeInterval(25 * 60)
        for (mode, hidden) in [(SessionMode.normal, false), (.strict, true)] {
            let compiled = policy([BlockRuleSet(targets: [instagram], activation: .sessionOnly)],
                                  session: SessionPolicy(sessionID: UUID(), mode: mode, end: end))

            #expect((AppBlocking.verdict(for: instagramID, policy: compiled, at: end) != .allow) == hidden)
        }
    }

    @Test func theReasonIsTheRuleThatNamesTheAppEvenDuringASession() {
        let session = SessionPolicy(sessionID: UUID(), mode: .strict, end: now.addingTimeInterval(600))
        let always = policy([BlockRuleSet(targets: [instagram], activation: .always)], session: session)
        let both = policy([BlockRuleSet(targets: [instagram], activation: .always),
                           BlockRuleSet(targets: [instagram], activation: .sessionOnly)], session: session)

        #expect(AppBlocking.verdict(for: instagramID, policy: always, at: now) == .hide(.always))
        #expect(AppBlocking.verdict(for: instagramID, policy: both, at: now) == .hide(.session(both.session!)))
    }

    @Test func anExceptionForTheAppAllowsItUntilItExpires() {
        let expiry = now.addingTimeInterval(10 * 60)
        let compiled = policy([BlockRuleSet(targets: [instagram], activation: .always)],
                              exceptions: [PolicyException(scope: .app(bundleID: "COM.burbn.instagram"), expiresAt: expiry)])

        #expect(AppBlocking.verdict(for: instagramID, policy: compiled, at: now) == .allow)
        #expect(AppBlocking.verdict(for: instagramID, policy: compiled, at: expiry) == .hide(.always))
    }

    @Test func anExceptionForAnotherAppOrASiteChangesNothing() {
        let compiled = policy([BlockRuleSet(targets: [instagram], activation: .always)],
                              exceptions: [PolicyException(scope: .app(bundleID: "com.tiktok"), expiresAt: now.addingTimeInterval(600)),
                                           PolicyException(scope: .site(domain: "instagram.com"), expiresAt: now.addingTimeInterval(600))])

        #expect(AppBlocking.verdict(for: instagramID, policy: compiled, at: now) == .hide(.always))
    }
}

@Suite("When an app verdict can change")
struct AppBlockingNextChangeTests {
    private let now = wednesdayMorningInBogota

    @Test func theEarliestExceptionExpiryBreakEndOrScheduleEdge() {
        let workdays = WeeklySchedule(days: [.mon, .tue, .wed, .thu, .fri], from: ClockTime(8, 0), to: ClockTime(18, 0), timeZone: bogota)
        let rules = [BlockRuleSet(targets: [instagram], activation: .schedule(workdays)),
                     BlockRuleSet(targets: [.app(bundleID: "com.tiktok", name: "TikTok")], activation: .sessionOnly)]
        let breakEnd = now.addingTimeInterval(15 * 60)
        let expiry = now.addingTimeInterval(10 * 60)
        let session = SessionPolicy(sessionID: UUID(), mode: .normal, end: now.addingTimeInterval(40 * 60), resumesAt: breakEnd)

        #expect(AppBlocking.nextChange(in: policy(rules), after: now) == instant("2026-10-14T18:00:00-05:00"))
        #expect(AppBlocking.nextChange(in: policy(rules, session: session), after: now) == breakEnd)
        #expect(AppBlocking.nextChange(in: policy(rules, session: session,
                                                  exceptions: [PolicyException(scope: .app(bundleID: instagramID), expiresAt: expiry)]),
                                       after: now) == expiry)
    }

    @Test func aNormalSessionEndsHidingAtItsEndAStrictOneWaitsForTheApp() {
        let rules = [BlockRuleSet(targets: [instagram], activation: .sessionOnly)]
        let end = now.addingTimeInterval(25 * 60)

        #expect(AppBlocking.nextChange(in: policy(rules, session: SessionPolicy(sessionID: UUID(), mode: .normal, end: end)), after: now) == end)
        #expect(AppBlocking.nextChange(in: policy(rules, session: SessionPolicy(sessionID: UUID(), mode: .strict, end: end)), after: now) == nil)
    }

    @Test func passedInstantsSiteOnlySchedulesAndNoPolicyGiveNothing() {
        let workdays = WeeklySchedule(days: [.mon], from: ClockTime(8, 0), to: ClockTime(18, 0), timeZone: bogota)
        let sites = policy([BlockRuleSet(targets: [.site(domain: "tiktok.com")], activation: .schedule(workdays))],
                           exceptions: [PolicyException(scope: .app(bundleID: instagramID), expiresAt: now)])

        #expect(AppBlocking.nextChange(in: sites, after: now) == nil)
        #expect(AppBlocking.nextChange(in: nil, after: now) == nil)
    }
}

@Suite("Apps already running when a session starts")
struct AppsToHideTests {
    private let now = wednesdayMorningInBogota

    @Test func everyRunningBlockedAppIsHiddenNotOnlyTheFrontOne() {
        let compiled = policy([BlockRuleSet(targets: [instagram], activation: .always),
                               BlockRuleSet(targets: [.app(bundleID: "com.tiktok", name: "TikTok")], activation: .sessionOnly)],
                              session: SessionPolicy(sessionID: UUID(), mode: .normal, end: now.addingTimeInterval(1500)))
        let running = ["com.apple.finder", "com.tiktok", "com.apple.TextEdit", "com.focuspilot.app", instagramID]

        #expect(AppBlocking.appsToHide(running: running, policy: compiled, ownBundleID: "com.focuspilot.app", at: now)
            == ["com.tiktok", instagramID])
    }

    @Test func appsWithAnExceptionStay() {
        let compiled = policy([BlockRuleSet(targets: [instagram], activation: .always)],
                              exceptions: [PolicyException(scope: .app(bundleID: instagramID), expiresAt: now.addingTimeInterval(300))])

        #expect(AppBlocking.appsToHide(running: [instagramID], policy: compiled, at: now).isEmpty)
    }
}
