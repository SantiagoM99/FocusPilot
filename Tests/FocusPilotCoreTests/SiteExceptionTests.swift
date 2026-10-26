import Foundation
import GRDB
import Testing
@testable import FocusPilotCore

/// One page as the app and the extension both read it (#14). The cases are
/// in `Tests/ChromeExtension/fixtures/pages.json`, which the extension's
/// node tests read too.
@Suite("One page")
struct PageAddressTests {
    private struct Fixture: Decodable {
        var canonical: [[String?]]
        var matches: [[Match]]

        enum Match: Decodable {
            case text(String), flag(Bool)
            init(from decoder: Decoder) throws {
                let value = try decoder.singleValueContainer()
                if let flag = try? value.decode(Bool.self) { self = .flag(flag) } else { self = .text(try value.decode(String.self)) }
            }
            var text: String { if case .text(let t) = self { t } else { "" } }
            var flag: Bool { if case .flag(let f) = self { f } else { false } }
        }
    }

    private static let fixture: Fixture = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "ChromeExtension/fixtures/pages.json")
        return try! JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }()

    @Test func pagesHaveTheCanonicalFormTheExtensionUses() {
        for pair in Self.fixture.canonical {
            #expect(PageAddress.canonical(pair[0]!) == pair[1], "\(pair[0]!)")
        }
    }

    @Test func aPageMatchesWhatTheExtensionMatches() {
        for row in Self.fixture.matches {
            #expect(PageAddress.matches(row[0].text, row[1].text) == row[2].flag, "\(row[0].text) vs \(row[1].text)")
        }
    }
}

@Suite("Timed exceptions for sites and pages")
struct SiteExceptionTests {
    private let blockYouTube = BlockRuleSet(targets: [.site(domain: "youtube.com")], activation: .sessionOnly)
    private let lecture = "https://www.youtube.com/watch?v=3kqW9M&t=42s"

    private func fixture(session mode: SessionMode? = .normal) async throws -> SessionFixture {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.saveRuleSet(blockYouTube)
        if let mode { try await fixture.coordinator.startSession(duration: 50 * 60, mode: mode) }
        return fixture
    }

    @Test func aSiteIsStoredAsTheDomainTheRulesBlock() async throws {
        let fixture = try await fixture()

        _ = try await fixture.coordinator.requestException(.site(domain: "https://www.YouTube.com/watch?v=1"), duration: 5 * 60)

        #expect(await fixture.publisher.published.last?.exceptions.map(\.scope) == [.site(domain: "youtube.com")])
    }

    @Test func aPageIsStoredInItsCanonicalForm() async throws {
        let fixture = try await fixture()

        let outcome = try await fixture.coordinator.requestException(.page(url: lecture), duration: 10 * 60)

        #expect(outcome == .granted(expiresAt: fixture.clock.now.addingTimeInterval(10 * 60)))
        #expect(await fixture.publisher.published.last?.exceptions.map(\.scope) == [.page(url: "https://youtube.com/watch?v=3kqW9M")])
    }

    @Test func somethingThatIsNotASiteOrPageIsRefused() async throws {
        let fixture = try await fixture()
        let published = await fixture.publisher.published.count

        await #expect(throws: ExceptionError.invalidSite) {
            try await fixture.coordinator.requestException(.site(domain: "not a site"), duration: 5 * 60)
        }
        await #expect(throws: ExceptionError.invalidPage) {
            try await fixture.coordinator.requestException(.page(url: "chrome://extensions"), duration: 5 * 60)
        }
        #expect(await fixture.publisher.published.count == published)
    }

    @Test func onlyASiteSomeRuleBlocksCanBeExcepted() async throws {
        let fixture = try await fixture()

        await #expect(throws: ExceptionError.notBlocked("example.com")) {
            try await fixture.coordinator.requestException(.page(url: "https://example.com/a"), duration: 5 * 60)
        }
        // A subdomain of a blocked site is blocked too.
        guard case .granted = try await fixture.coordinator.requestException(.site(domain: "music.youtube.com"), duration: 5 * 60) else {
            Issue.record("a subdomain of a blocked site was refused")
            return
        }
    }

    /// One shared deadline: a second request for something already allowed,
    /// from another Chrome profile or the app, never moves the expiry.
    @Test func askingAgainForWhatIsAlreadyAllowedKeepsItsExpiry() async throws {
        let fixture = try await fixture()
        let expiry = fixture.clock.now.addingTimeInterval(10 * 60)
        _ = try await fixture.coordinator.requestException(.page(url: lecture), duration: 10 * 60)
        let published = await fixture.publisher.published.count

        fixture.advance(minutes: 3)
        #expect(try await fixture.coordinator.requestException(.page(url: "https://youtube.com/watch?v=3kqW9M"), duration: 20 * 60)
            == .granted(expiresAt: expiry))
        #expect(await fixture.publisher.published.count == published, "nothing new to publish")
    }

    @Test func aSiteExceptionCoversItsPagesButAPageDoesNotCoverTheSite() async throws {
        let fixture = try await fixture()
        _ = try await fixture.coordinator.requestException(.page(url: lecture), duration: 5 * 60)

        let site = try await fixture.coordinator.requestException(.site(domain: "youtube.com"), duration: 20 * 60)
        #expect(site == .granted(expiresAt: fixture.clock.now.addingTimeInterval(20 * 60)))
        #expect(try await fixture.coordinator.requestException(.page(url: "https://youtube.com/watch?v=other"), duration: 5 * 60)
            == .granted(expiresAt: fixture.clock.now.addingTimeInterval(20 * 60)))
        #expect(await fixture.publisher.published.last?.exceptions.count == 2)
    }

    @Test func afterItExpiresTheSameRequestIsGrantedAfresh() async throws {
        let fixture = try await fixture()
        _ = try await fixture.coordinator.requestException(.site(domain: "youtube.com"), duration: 5 * 60)

        fixture.advance(minutes: 5)
        #expect(try await fixture.coordinator.requestException(.site(domain: "youtube.com"), duration: 5 * 60)
            == .granted(expiresAt: fixture.clock.now.addingTimeInterval(5 * 60)))
    }

    @Test func aStrictStartCancelsSiteExceptionsAndANewOneNeedsConfirmation() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.saveRuleSet(blockYouTube)
        _ = try await fixture.coordinator.requestException(.site(domain: "youtube.com"), duration: 20 * 60)
        try await fixture.coordinator.startSession(duration: 50 * 60, mode: .strict)
        // Starting the strict session cancelled it (decision 0003, 2026-10-22).
        #expect(await fixture.publisher.published.last?.exceptions == [])

        #expect(try await fixture.coordinator.requestException(.page(url: lecture), duration: 5 * 60, reason: "Lecture") == .needsConfirmation)
    }

    @Test func inAStrictSessionWhatIsAlreadyAllowedNeedsNoNewWait() async throws {
        let fixture = try await fixture(session: .strict)
        let request = { (confirmed: Bool) in
            try await fixture.coordinator.requestException(.site(domain: "youtube.com"), duration: 10 * 60, reason: "Lecture", confirmed: confirmed)
        }
        _ = try await request(false)
        _ = try await request(true)
        fixture.advance(seconds: 60)
        let expiry = fixture.clock.now.addingTimeInterval(10 * 60)
        #expect(try await request(false) == .granted(expiresAt: expiry))

        // Another profile asks for one of its pages: no confirmation, same expiry.
        #expect(try await fixture.coordinator.requestException(.page(url: lecture), duration: 5 * 60, reason: "Lecture") == .granted(expiresAt: expiry))
    }

    @Test func sleepOrARelaunchNeverExtendsASiteException() async throws {
        let fixture = try await fixture()
        let expiry = fixture.clock.now.addingTimeInterval(10 * 60)
        _ = try await fixture.coordinator.requestException(.page(url: lecture), duration: 10 * 60)

        // The Mac sleeps for 7 minutes, then the app is relaunched.
        fixture.advance(minutes: 7)
        let relaunched = try fixture.relaunched()
        try await relaunched.launch()
        #expect(await relaunched.snapshot().policy?.exceptions.map(\.expiresAt) == [expiry])
        #expect(await relaunched.snapshot().nextDeadline == expiry)

        // It sleeps past the expiry: waking drops the exception.
        fixture.advance(minutes: 4)
        try await relaunched.reconcile()
        #expect(await relaunched.snapshot().policy?.exceptions == [])
    }
}

@Suite("Site exceptions in Settings")
struct SiteExceptionTextTests {
    private let youtube = BlockRuleSet(targets: [.site(domain: "youtube.com")], activation: .always)
    private let now = wednesdayMorningInBogota
    private func status(_ exceptions: [PolicyException], rule: BlockRuleSet? = nil, at instant: Date? = nil) -> String {
        RuleText.status(rule ?? youtube, at: instant ?? now, sessionRulesApply: false, exceptions: exceptions)
    }
    private func expiring(_ scope: ExceptionScope, minutes: Double = 8) -> PolicyException {
        PolicyException(scope: scope, expiresAt: now.addingTimeInterval(minutes * 60 - 1))
    }

    @Test func aSiteRuleShowsItsExceptionsTimeLeft() {
        #expect(status([expiring(.site(domain: "youtube.com"))]) == "Exception · whole site · 8 min left")
        #expect(status([expiring(.page(url: "https://youtube.com/watch?v=1"))]) == "Exception · 1 page · 8 min left")
        #expect(status([expiring(.page(url: "https://youtube.com/watch?v=1")), expiring(.page(url: "https://youtube.com/watch?v=2"), minutes: 12)])
            == "Exception · 2 pages · 12 min left")
        #expect(status([expiring(.page(url: "https://youtube.com/watch?v=1")), expiring(.site(domain: "youtube.com"), minutes: 3)])
            == "Exception · whole site · 3 min left", "a site exception covers its pages")
    }

    @Test func otherSitesAndExpiredExceptionsDoNotCount() {
        let expired = expiring(.site(domain: "youtube.com"))
        #expect(status([expiring(.site(domain: "instagram.com"))]) == "Blocked now")
        #expect(status([expired], at: expired.expiresAt) == "Blocked now")
        #expect(status([expiring(.app(bundleID: "com.google.youtube"))]) == "Blocked now")
    }

    @Test func whatTheOwnerTypesBecomesASiteOrAPage() {
        #expect(ExceptionScope.requested("youtube.com/watch?v=1", wholeSite: true) == .site(domain: "youtube.com/watch?v=1"))
        #expect(ExceptionScope.requested("youtube.com/watch?v=1", wholeSite: false) == .page(url: "https://youtube.com/watch?v=1"))
        #expect(ExceptionScope.requested(" http://example.com/a ", wholeSite: false) == .page(url: "http://example.com/a"))
        #expect(ExceptionScope.requested("   ", wholeSite: true) == nil)
    }
}

@Suite("Site exceptions in the menu bar")
struct SiteExceptionLineTests {
    private let now = wednesdayMorningInBogota

    @Test func eachRunningSiteOrPageExceptionHasALine() {
        let exceptions = [
            PolicyException(scope: .page(url: "https://youtube.com/watch?v=1"), expiresAt: now.addingTimeInterval(8 * 60 - 1)),
            PolicyException(scope: .site(domain: "instagram.com"), expiresAt: now.addingTimeInterval(19 * 60 + 30)),
            PolicyException(scope: .app(bundleID: "com.burbn.instagram"), expiresAt: now.addingTimeInterval(600)),
            PolicyException(scope: .site(domain: "reddit.com"), expiresAt: now),
        ]
        #expect(SiteExceptionText.lines(exceptions, at: now) == [
            "Exception · 1 page on youtube.com · 8 min left",
            "Exception · all of instagram.com · 20 min left",
        ])
    }
}

@Suite("A strict-session exception keeps its confirmed reason")
struct PendingReasonTests {
    @Test func theReasonGivenAtConfirmationCarriesThroughTheWait() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.saveRuleSet(BlockRuleSet(targets: [.site(domain: "youtube.com")], activation: .sessionOnly))
        try await fixture.coordinator.startSession(duration: 50 * 60, mode: .strict)
        let lecture = ExceptionScope.page(url: "https://youtube.com/watch?v=1")

        _ = try await fixture.coordinator.requestException(lecture, duration: 600, reason: "Lecture for §4.2", confirmed: true)
        #expect(await fixture.coordinator.snapshot().pendingException?.reason == "Lecture for §4.2")

        // Reopened elsewhere (another profile, the app) without the reason typed again.
        fixture.advance(seconds: 60)
        #expect(try await fixture.coordinator.requestException(lecture, duration: 600)
            == .granted(expiresAt: fixture.clock.now.addingTimeInterval(600)))
        await #expect(throws: ExceptionError.reasonRequired) {
            try await fixture.coordinator.requestException(.site(domain: "youtube.com"), duration: 300)
        }
    }
}

@Suite("Grants from Chrome are announced")
struct ExceptionNoticeTests {
    @Test func theNoticeSaysWhatWasAllowedAndUntilWhen() {
        let until = instant("2026-10-14T10:32:00-05:00")
        let bogota = TimeZone(identifier: "America/Bogota")!
        #expect(ExceptionNoticeText.grantedFromChrome(.page(url: "https://youtube.com/watch?v=1"), until: until, in: bogota)
            == ExceptionNoticeText(title: "Exception allowed from Chrome", body: "1 page on youtube.com until 10:32"))
        #expect(ExceptionNoticeText.grantedFromChrome(.site(domain: "youtube.com"), until: until, in: bogota).body == "All of youtube.com until 10:32")
    }
}

/// Profiles and the app share one strict wait; none may lose another's.
@Suite("One strict wait across profiles")
struct SharedStrictWaitTests {
    private let lecture = ExceptionScope.page(url: "https://youtube.com/watch?v=1")
    private let other = ExceptionScope.page(url: "https://youtube.com/watch?v=2")

    private func waiting() async throws -> SessionFixture {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.saveRuleSet(BlockRuleSet(targets: [.site(domain: "youtube.com")], activation: .sessionOnly))
        try await fixture.coordinator.startSession(duration: 50 * 60, mode: .strict)
        _ = try await fixture.coordinator.requestException(lecture, duration: 600, reason: "Lecture", confirmed: true)
        return fixture
    }

    @Test func anotherUnconfirmedRequestLeavesTheConfirmedWaitAlone() async throws {
        let fixture = try await waiting()

        #expect(try await fixture.coordinator.requestException(other, duration: 300, reason: "Other") == .needsConfirmation)
        #expect(await fixture.coordinator.snapshot().pendingException?.scope == lecture)

        fixture.advance(seconds: 60)
        guard case .granted = try await fixture.coordinator.requestException(lecture, duration: 600) else {
            Issue.record("the confirmed wait was lost")
            return
        }
    }

    @Test func cancellingAnotherScopeKeepsTheWait() async throws {
        let fixture = try await waiting()

        await fixture.coordinator.cancelException(for: other)
        #expect(await fixture.coordinator.snapshot().pendingException?.scope == lecture)
        await fixture.coordinator.cancelException(for: .page(url: "https://www.youtube.com/watch?v=1&t=5"))
        #expect(await fixture.coordinator.snapshot().pendingException == nil)
    }
}

@Suite("Cancelling a strict wait")
struct CancelStrictWaitTests {
    @Test func aPageClosingItsFormLeavesTheWholeSitesWaitAlone() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.saveRuleSet(BlockRuleSet(targets: [.site(domain: "youtube.com")], activation: .sessionOnly))
        try await fixture.coordinator.startSession(duration: 50 * 60, mode: .strict)
        _ = try await fixture.coordinator.requestException(.site(domain: "youtube.com"), duration: 600, reason: "Course", confirmed: true)

        await fixture.coordinator.cancelException(for: .page(url: "https://youtube.com/watch?v=1"))

        #expect(await fixture.coordinator.snapshot().pendingException?.scope == .site(domain: "youtube.com"))
    }
}

/// Which page was allowed and why is private (DATA_AND_MEMORY): it is kept
/// only while the exception runs.
@Suite("Ended exceptions keep no page or reason")
struct EndedExceptionPrivacyTests {
    private func rows(_ fixture: SessionFixture) async throws -> [TimedException] {
        try await TaskRepository(location: fixture.location).ownerDatabase.read { db in
            try ExceptionRow.order(Column("id")).fetchAll(db).map { try $0.exception() }
        }
    }

    private func fixture() async throws -> SessionFixture {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.saveRuleSet(BlockRuleSet(targets: [.site(domain: "youtube.com")], activation: .sessionOnly))
        return fixture
    }

    @Test func anExpiredPageExceptionLosesItsAddressAndReason() async throws {
        let fixture = try await fixture()
        try await fixture.coordinator.startSession(duration: 50 * 60, mode: .strict)
        let page = ExceptionScope.page(url: "https://youtube.com/watch?v=private")
        _ = try await fixture.coordinator.requestException(page, duration: 300, reason: "Lecture for §4.2", confirmed: true)
        fixture.advance(seconds: 60)
        _ = try await fixture.coordinator.requestException(page, duration: 300, reason: "Lecture for §4.2")
        _ = try await fixture.coordinator.requestException(.site(domain: "youtube.com"), duration: 1200, reason: "Course", confirmed: true)
        fixture.advance(seconds: 60)
        _ = try await fixture.coordinator.requestException(.site(domain: "youtube.com"), duration: 1200, reason: "Course")

        #expect(try await rows(fixture).map(\.reason) == ["Lecture for §4.2", "Course"], "kept while running")

        fixture.advance(minutes: 5)
        try await fixture.coordinator.reconcile()

        let after = try await rows(fixture)
        #expect(after[0].scope == .page(url: ""))
        #expect(after[0].reason == nil)
        #expect(after[1].scope == .site(domain: "youtube.com"), "the running one is untouched")
        #expect(after[1].reason == "Course")
    }

    @Test func exceptionsCancelledByAStrictStartAreForgottenAtOnce() async throws {
        let fixture = try await fixture()
        _ = try await fixture.coordinator.requestException(.page(url: "https://youtube.com/watch?v=private"), duration: 600, reason: "Note")

        try await fixture.coordinator.startSession(duration: 50 * 60, mode: .strict)

        #expect(try await rows(fixture).map(\.scope) == [.page(url: "")])
        #expect(try await rows(fixture).map(\.reason) == [nil])
    }
}

@Suite("Only new grants from Chrome are announced")
struct ChromeGrantNoticeTests {
    @Test func aNewGrantFromChromeIsAnnouncedOnceAndNothingElseIs() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.saveRuleSet(BlockRuleSet(targets: [.site(domain: "youtube.com")], activation: .always))
        let page = ExceptionScope.page(url: "https://www.youtube.com/watch?v=1")
        let until = fixture.clock.now.addingTimeInterval(600)

        _ = try await fixture.coordinator.requestException(page, duration: 600, origin: .chrome)
        _ = try await fixture.coordinator.requestException(page, duration: 1200, origin: .chrome)  // already covered
        _ = try await fixture.coordinator.requestException(.site(domain: "youtube.com"), duration: 300)  // from the app

        #expect(await fixture.notices.delivered == [.exceptionGrantedFromChrome(.page(url: "https://youtube.com/watch?v=1"), until: until)])
    }
}
