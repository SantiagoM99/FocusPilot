import Foundation
import Testing
@testable import FocusPilotCore

@Suite("Settings › Blocking rows")
struct BlockingRowsTests {
    private let workdays = WeeklySchedule(days: [.mon, .tue, .wed, .thu, .fri], from: ClockTime(8, 0), to: ClockTime(18, 0), timeZone: bogota)
    private let steam = ActivityTarget.app(bundleID: "com.valve.steam", name: "Steam")
    private let now = wednesdayMorningInBogota

    @Test func activationsReadAsTheBoardWritesThem() {
        #expect(RuleText.activationLabel(.always) == "Always")
        #expect(RuleText.activationLabel(.sessionOnly) == "During focus")
        #expect(RuleText.activationLabel(.schedule(workdays)) == "Weekdays 8:00 to 18:00")
    }

    @Test(arguments: [
        (Set<Weekday>([.sat, .sun]), "Weekends 8:00 to 18:00"),
        (Set(Weekday.allCases), "Every day 8:00 to 18:00"),
        (Set<Weekday>([.mon, .wed]), "Mon, Wed 8:00 to 18:00"),
    ])
    func otherDaysAreNamed(days: Set<Weekday>, label: String) {
        var schedule = workdays
        schedule.days = days
        #expect(RuleText.activationLabel(.schedule(schedule)) == label)
    }

    @Test func eachSiteAndAppGetsItsOwnRowInItsList() {
        let mixed = BlockRuleSet(id: 1, targets: [.site(domain: "x.com"), steam, .site(domain: "reddit.com")], activation: .schedule(workdays))
        let session = BlockRuleSet(id: 2, targets: [.site(domain: "youtube.com")], activation: .sessionOnly)
        let lists = BlockingLists(rules: [mixed, session], allowed: [], at: now)

        #expect(lists.sites.map(\.title) == ["x.com", "reddit.com", "youtube.com"])
        #expect(lists.sites.map(\.detail) == ["Weekdays 8:00 to 18:00", "Weekdays 8:00 to 18:00", "During focus"])
        #expect(lists.apps.map(\.title) == ["Steam"])
        #expect(Set(lists.sites.map(\.id)).count == 3)
    }

    @Test func aRunningExceptionReplacesTheActivationOnThatRowOnly() {
        let rule = BlockRuleSet(id: 1, targets: [.site(domain: "youtube.com"), .site(domain: "x.com")], activation: .always)
        let exception = PolicyException(scope: .site(domain: "youtube.com"), expiresAt: now.addingTimeInterval(8 * 60 - 1))
        let lists = BlockingLists(rules: [rule], allowed: [], at: now, exceptions: [exception])

        #expect(lists.sites.map(\.detail) == ["Exception · whole site · 8 min left", "Always"])
    }

    @Test func allowedRowsNameTheirKind() {
        let allowed = [
            AllowedActivity(id: 1, name: "Zotero", target: .app(bundleID: "org.zotero.zotero", name: "Zotero")),
            AllowedActivity(id: 2, name: "Overleaf", target: .site(domain: "overleaf.com")),
            AllowedActivity(id: 3, name: "Herdr", target: .tool(command: "herdr"), source: .seeded),
        ]
        let rows = BlockingLists(rules: [], allowed: allowed, at: now).allowed

        #expect(rows.map(\.title) == ["Zotero", "overleaf.com", "Herdr"])
        #expect(rows.map(\.detail) == ["App", "Site", "Tool"])
    }

    @Test func removingARowRemovesOnlyThatTarget() {
        let rule = BlockRuleSet(id: 7, targets: [.site(domain: "x.com"), steam], activation: .always, revision: 3)
        var left = rule
        left.targets = [steam]

        #expect(RuleEdit.removing(.site(domain: "x.com"), from: rule) == .save(left))
    }

    @Test func removingTheLastTargetDeletesTheRule() {
        let rule = BlockRuleSet(id: 7, targets: [steam], activation: .always)

        #expect(RuleEdit.removing(steam, from: rule) == .delete(7))
    }

    @Test func removingOneTargetDuringAStrictSessionStillAsksFirst() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.saveRuleSet(BlockRuleSet(targets: [.site(domain: "x.com"), .site(domain: "reddit.com")], activation: .always))
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .strict)
        let rule = try await fixture.coordinator.ruleSets()[0]

        guard case .save(let left)? = RuleEdit.removing(.site(domain: "x.com"), from: rule) else {
            Issue.record("expected a save")
            return
        }

        #expect(try await fixture.coordinator.saveRuleSet(left) == .needsConfirmation)
        #expect(try await fixture.coordinator.ruleSets()[0].targets.count == 2)
    }
}

@MainActor
@Suite("Session preferences")
struct SessionPreferencesTests {
    private let defaults = UserDefaults(suiteName: "FocusPilotTests-\(UUID().uuidString)")!

    @Test func startsAtFiftyMinutesAndNotStrict() {
        let preferences = SessionPreferences(defaults: defaults)

        #expect(preferences.defaultMinutes == 50)
        #expect(!preferences.strictByDefault)
    }

    @Test func choicesAreRemembered() {
        let preferences = SessionPreferences(defaults: defaults)
        preferences.defaultMinutes = 90
        preferences.strictByDefault = true

        let reopened = SessionPreferences(defaults: defaults)
        #expect(reopened.defaultMinutes == 90)
        #expect(reopened.strictByDefault)
    }

    @Test func aLengthThatIsNotOfferedFallsBackToFifty() {
        defaults.set(7, forKey: "defaultSessionMinutes")

        #expect(SessionPreferences(defaults: defaults).defaultMinutes == 50)
    }

    @Test func offersTheBoardsLengths() {
        #expect(SessionPreferences.lengths == [50, 25, 90])
    }
}

@Suite("Timed exception lengths")
struct TimedExceptionLengthTests {
    @Test func offeredLengthsAreTenTwentyAndFortyFiveMinutes() {
        #expect(TimedException.durations == [600, 1200, 2700])
    }
}

@Suite("Where the blocked page sends the owner back")
struct WorkPageTests {
    @Test(arguments: [("https://www.overleaf.com/project/1", "Overleaf"), ("arxiv.org/abs/1", "Arxiv"), ("docs.google.com/d/1", "Docs")])
    func aPageIsNamedAfterItsSite(url: String, name: String) throws {
        #expect(try WebPageLink(url).siteName == name)
    }

    @Test func theFirstWebPageInTheTasksOpenListIsSentToChrome() async throws {
        let fixture = try await SessionFixture()
        let task = try await fixture.coordinator.todayTasks()[0].id
        let folder = try makeTemporaryDirectory()
        let linkedFolder = try await fixture.coordinator.linkFolder(folder, to: .task(task))
        let later = try await fixture.coordinator.linkWebPage("arxiv.org/abs/1", to: .task(task))
        let first = try await fixture.coordinator.linkWebPage("https://www.overleaf.com/project/1", to: .task(task))
        try await fixture.coordinator.setLaunch(.resource(linkedFolder.id), included: true)
        try await fixture.coordinator.setLaunch(.resource(first.id), included: true)
        try await fixture.coordinator.setLaunch(.resource(later.id), included: true)

        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)

        let focus = try #require(await fixture.publisher.deliveries.last?.focus)
        #expect(focus.resourceName == "Overleaf")
        #expect(focus.resourceURL == "https://www.overleaf.com/project/1")
    }

    @Test func aTaskWithNoWebPageSendsNone() async throws {
        let fixture = try await SessionFixture()

        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)

        let focus = try #require(await fixture.publisher.deliveries.last?.focus)
        #expect(focus.resourceName == nil)
        #expect(focus.resourceURL == nil)
    }
}
