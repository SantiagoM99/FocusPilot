import Foundation
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
