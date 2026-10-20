import Foundation
import Testing
@testable import FocusPilotCore

@Suite("Rules through the coordinator")
struct RuleCoordinatorTests {
    private let youtube = BlockRuleSet(targets: [.site(domain: "youtube.com")], activation: .sessionOnly)

    @Test func editingARulePublishesANewRevisionWithTheRule() async throws {
        let fixture = try await SessionFixture()

        try await fixture.coordinator.saveRuleSet(BlockRuleSet(targets: [.site(domain: "instagram.com")], activation: .always))

        let policy = try #require(await fixture.publisher.published.last)
        #expect(policy.revision == 1)
        #expect(policy.always.domains == ["instagram.com"])
        #expect(await fixture.coordinator.snapshot().policy == policy)
    }

    @Test func everyRuleEditGetsAHigherRevision() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.saveRuleSet(youtube)
        var rule = try #require(await fixture.coordinator.ruleSets().first)
        rule.activation = .always

        try await fixture.coordinator.saveRuleSet(rule)
        try await fixture.coordinator.deleteRuleSet(rule.id!)

        #expect(await fixture.publisher.published.map(\.revision) == [1, 2, 3])
        #expect(await fixture.publisher.published.last?.always.domains == [])
    }

    @Test func sessionOnlyRulesJoinThePolicyWhenASessionStarts() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.saveRuleSet(youtube)
        #expect(await fixture.publisher.published.last?.session == nil)

        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)

        #expect(await fixture.publisher.published.last?.session?.targets.domains == ["youtube.com"])
    }

    @Test func editingDuringASessionKeepsTheSessionInThePolicy() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .strict)

        try await fixture.coordinator.saveRuleSet(youtube)

        let session = try #require(await fixture.publisher.published.last?.session)
        #expect(session.mode == .strict)
        #expect(session.targets.domains == ["youtube.com"])
    }

    @Test func strictPausesKeepSessionOnlyRulesNormalPausesLiftThem() async throws {
        for (mode, kept) in [(SessionMode.strict, true), (.normal, false)] {
            let fixture = try await SessionFixture()
            try await fixture.coordinator.saveRuleSet(youtube)
            try await fixture.coordinator.startSession(duration: 25 * 60, mode: mode)

            try await fixture.coordinator.pause()

            #expect((await fixture.publisher.published.last?.session?.targets.domains == ["youtube.com"]) == kept)
        }
    }

    @Test func launchPublishesTheRulesEvenWithoutASession() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.saveRuleSet(BlockRuleSet(targets: [.site(domain: "instagram.com")], activation: .always))
        let relaunched = try fixture.relaunched()

        try await relaunched.launch()

        #expect(await fixture.publisher.published.map(\.revision) == [1, 2])
        #expect(await relaunched.snapshot().policy?.always.domains == ["instagram.com"])
    }

    @Test func refusedEditsPublishNothing() async throws {
        let fixture = try await SessionFixture()

        await #expect(throws: RuleError.self) {
            try await fixture.coordinator.saveRuleSet(BlockRuleSet(targets: [.site(domain: "overleaf.com")], activation: .always))
        }
        #expect(await fixture.publisher.published.isEmpty)
    }

    @Test func allowedListEditsPublishToo() async throws {
        let fixture = try await SessionFixture()

        try await fixture.coordinator.allow(AllowedActivity(name: "Zotero", target: .app(bundleID: "org.zotero.zotero", name: "Zotero")))

        #expect(await fixture.publisher.published.last?.allowed.apps.contains("org.zotero.zotero") == true)
        let zotero = try #require(await fixture.coordinator.allowedActivities().last)
        try await fixture.coordinator.removeAllowed(zotero.id!)
        #expect(await fixture.publisher.published.last?.allowed.apps.contains("org.zotero.zotero") == false)
    }
}

@Suite("Rule status text")
struct RuleStatusTests {
    private let workdays = WeeklySchedule(days: [.mon, .tue, .wed, .thu, .fri], from: ClockTime(8, 0), to: ClockTime(18, 0), timeZone: bogota)

    @Test func alwaysIsBlockedNow() {
        #expect(RuleText.status(.always, at: wednesdayMorningInBogota, sessionRulesApply: false) == "Blocked now")
    }

    @Test func sessionOnlyDependsOnSessionRules() {
        #expect(RuleText.status(.sessionOnly, at: wednesdayMorningInBogota, sessionRulesApply: true) == "Blocked now")
        #expect(RuleText.status(.sessionOnly, at: wednesdayMorningInBogota, sessionRulesApply: false) == "During focus sessions")
    }

    @Test func schedulesSayWhenTheyEndOrStart() {
        #expect(RuleText.status(.schedule(workdays), at: wednesdayMorningInBogota, sessionRulesApply: false) == "Ends 18:00")
        #expect(RuleText.status(.schedule(workdays), at: instant("2026-10-14T07:00:00-05:00"), sessionRulesApply: false) == "Starts 08:00")
        #expect(RuleText.status(.schedule(workdays), at: instant("2026-10-16T19:00:00-05:00"), sessionRulesApply: false) == "Starts Mon 08:00")
    }

    @Test func activationNames() {
        #expect(RuleText.activationName(.always) == "Always")
        #expect(RuleText.activationName(.sessionOnly) == "Session only")
        #expect(RuleText.activationName(.schedule(workdays)) == "Schedule")
    }

    @Test func sessionRulesApplyWhileTheEngineWouldPublishThem() {
        let start = FocusSession.sampleStart
        var strict = FocusSession.sample(phase: .paused(since: start))
        strict.mode = .strict

        #expect(FocusSnapshot(session: .sample(phase: .running)).sessionRulesApply)
        #expect(FocusSnapshot(session: strict).sessionRulesApply)
        #expect(!FocusSnapshot(session: .sample(phase: .paused(since: start))).sessionRulesApply)
        #expect(!FocusSnapshot(session: .sample(phase: .onBreak(until: start.addingTimeInterval(300)))).sessionRulesApply)
        #expect(!FocusSnapshot().sessionRulesApply)
    }
}

@Suite("Rule error text")
struct RuleErrorTextTests {
    @Test func refusalsSayWhatToDo() {
        #expect(RuleErrorText.message(.alreadyAllowed(.site(domain: "overleaf.com"))) == "overleaf.com is in Allowed. Remove it there first.")
        #expect(RuleErrorText.message(.alreadyBlocked(.app(bundleID: "com.burbn.instagram", name: "Instagram")))
            == "Instagram is blocked by a rule. Remove it there first.")
        #expect(RuleErrorText.message(.notBlockable(.tool(command: "herdr"))) == "herdr is a command-line tool and can't be blocked.")
        #expect(RuleErrorText.message(.ruleChanged) == "This rule changed since you opened it. Check it and try again.")
    }
}

@Suite("App rule status")
struct AppRuleStatusTests {
    @Test func appOnlyRulesSayHidingIsNotBuiltYet() {
        let apps = BlockRuleSet(targets: [.app(bundleID: "com.burbn.instagram", name: "Instagram")], activation: .always)
        let mixed = BlockRuleSet(targets: [.app(bundleID: "com.burbn.instagram", name: "Instagram"), .site(domain: "instagram.com")], activation: .always)

        #expect(RuleText.status(apps, at: wednesdayMorningInBogota, sessionRulesApply: false) == "Not hidden yet (#25)")
        #expect(RuleText.status(mixed, at: wednesdayMorningInBogota, sessionRulesApply: false) == "Blocked now")
    }
}
