import Foundation
import Testing
@testable import FocusPilotCore

@Suite("Blocked app panel text")
struct BlockedAppTextTests {
    private let now = wednesdayMorningInBogota
    private let workdays = WeeklySchedule(days: [.mon, .tue, .wed, .thu, .fri], from: ClockTime(8, 0), to: ClockTime(18, 0), timeZone: bogota)

    @Test func duringASessionItShowsTheTimeLeftAndTheTask() {
        var session = FocusSession.sample(phase: .running)
        session.plannedEnd = now.addingTimeInterval(24 * 60 + 8)
        let text = BlockedAppText(appName: "Instagram", reason: .always, session: session, at: now)

        #expect(text.headline == "Focus session · 24:08 left")
        #expect(text.detail == "You're working on \(session.action)")
        #expect(text.footer == "Instagram was hidden, not quit. Nothing was closed. Exceptions cover the whole app.")
    }

    @Test func outsideASessionAScheduleSaysWhenItEnds() {
        let text = BlockedAppText(appName: "Instagram", reason: .schedule(workdays), session: nil, at: instant("2026-10-14T14:43:00-05:00"))

        #expect(text.headline == "No session running")
        #expect(text.detail == "Blocked by a schedule · Mon–Fri 08:00–18:00 · America/Bogota · ends today at 18:00 (in 3 h 17 min)")
    }

    @Test func aScheduleEndingAnotherDayNamesTheDay() {
        let nights = WeeklySchedule(days: [.wed], from: ClockTime(22, 0), to: ClockTime(2, 0), timeZone: bogota)
        let text = BlockedAppText(appName: "Instagram", reason: .schedule(nights), session: nil, at: instant("2026-10-14T23:30:00-05:00"))

        #expect(text.detail == "Blocked by a schedule · Wed 22:00–02:00 · America/Bogota · ends Thu at 02:00 (in 2 h 30 min)")
    }

    @Test func alwaysOnRulesHaveNoEnd() {
        let text = BlockedAppText(appName: "Instagram", reason: .always, session: nil, at: now)

        #expect(text.headline == "No session running")
        #expect(text.detail == "Blocked at all times")
    }

    @Test func aStrictExceptionCountsDownToWhenItCanBeAsked() {
        #expect(BlockedAppText.exceptionButton(availableAt: nil, now: now) == "Request a timed exception…")
        #expect(BlockedAppText.exceptionButton(availableAt: now.addingTimeInterval(42), now: now) == "Request a timed exception… available in 0:42")
        #expect(BlockedAppText.exceptionButton(availableAt: now, now: now) == "Allow now")
    }

    @Test func theAllowButtonCountsDownTheStrictWait() {
        #expect(BlockedAppText.allowButton(availableAt: nil, now: now) == "Allow")
        #expect(BlockedAppText.allowButton(availableAt: now.addingTimeInterval(42), now: now) == "Allow in 0:42")
        #expect(BlockedAppText.allowButton(availableAt: now, now: now) == "Allow now")
    }
}

@Suite("Apps protection line")
struct AppProtectionTextTests {
    private let now = wednesdayMorningInBogota
    private let instagram = ActivityTarget.app(bundleID: "com.burbn.instagram", name: "Instagram")
    private let tiktok = ActivityTarget.app(bundleID: "com.tiktok", name: "TikTok")

    private func policy(_ rules: [BlockRuleSet], session: SessionPolicy? = nil, exceptions: [PolicyException] = []) -> CompiledPolicy {
        CompiledPolicy(revision: 1, effectiveAt: now, rules: PolicyCompiler.compile(rules: rules, allowed: [], session: session, exceptions: exceptions))
    }

    @Test func namesTheAppsHiddenNowAndThatItNeedsFocusPilotRunning() {
        let rules = [BlockRuleSet(targets: [instagram, .site(domain: "instagram.com")], activation: .always),
                     BlockRuleSet(targets: [tiktok], activation: .sessionOnly)]

        let line = AppProtectionText(rules: rules, policy: policy(rules), at: now)

        #expect(line.summary == "Apps protected · Instagram")
        #expect(line.detail == "Only while FocusPilot is running")
    }

    @Test func anExceptionOrNoAppRulesSayNoAppIsHidden() {
        let rules = [BlockRuleSet(targets: [instagram], activation: .always)]
        let excepted = policy(rules, exceptions: [PolicyException(scope: .app(bundleID: "com.burbn.instagram"), expiresAt: now.addingTimeInterval(600))])

        #expect(AppProtectionText(rules: rules, policy: excepted, at: now).summary == "No apps hidden now · Instagram has an exception")
        #expect(AppProtectionText(rules: [], policy: policy([]), at: now).summary == "No apps blocked")
    }

    @Test func preflightListsTheAppsASessionWouldHide() {
        let rules = [BlockRuleSet(targets: [instagram], activation: .always),
                     BlockRuleSet(targets: [tiktok], activation: .sessionOnly),
                     BlockRuleSet(targets: [.site(domain: "youtube.com")], activation: .sessionOnly)]

        #expect(AppProtectionText.preflight(rules: rules, at: now) == "Instagram, TikTok hidden on open · only while FocusPilot runs")
        #expect(AppProtectionText.preflight(rules: [], at: now) == "No apps blocked")
    }
}
