import Testing
@testable import FocusPilotCore

@Suite("Site domains")
struct SiteDomainTests {
    @Test(arguments: [
        ("instagram.com", "instagram.com"),
        ("  Instagram.COM ", "instagram.com"),
        ("www.youtube.com", "youtube.com"),
        ("https://www.youtube.com/watch?v=abc", "youtube.com"),
        ("http://news.ycombinator.com:8080/item", "news.ycombinator.com"),
        ("reddit.com/r/swift", "reddit.com"),
        ("example.co.uk.", "example.co.uk"),
        // Review of PR #39: international names come out as punycode.
        ("münchen.de", "xn--mnchen-3ya.de"),
        ("xn--mnchen-3ya.de", "xn--mnchen-3ya.de"),
        ("https://MÜNCHEN.de/karte", "xn--mnchen-3ya.de"),
    ])
    func typedSitesBecomeDomains(typed: String, domain: String) {
        #expect(SiteDomain.normalized(typed) == domain)
    }

    @Test(arguments: ["", "   ", "instagram", "not a site", "-bad.com", "bad-.com", "exa_mple.com", "localhost", "https://"])
    func textThatIsNotADomainIsRejected(typed: String) {
        #expect(SiteDomain.normalized(typed) == nil)
    }

    // The editor says the whole domain is blocked when a page was typed.
    @Test(arguments: [
        ("youtube.com", false),
        ("https://youtube.com/", false),
        ("youtube.com/watch?v=1", true),
        ("https://www.youtube.com/@channel", true),
        ("youtube.com?q=1", true),
        ("not a site", false),
    ])
    func typedPagesAreNoticed(typed: String, page: Bool) {
        #expect(SiteDomain.namesAPage(typed) == page)
    }
}

@Suite("Activity target conflicts")
struct ActivityConflictTests {
    private let allowed = [
        AllowedActivity(id: 1, name: "Overleaf", target: .site(domain: "overleaf.com"), source: .seeded),
        AllowedActivity(id: 2, name: "Finder", target: .app(bundleID: "com.apple.finder", name: "Finder"), source: .seeded),
    ]
    private let rules = [BlockRuleSet(id: 7, targets: [.site(domain: "instagram.com")], activation: .always)]

    @Test func blockingSomethingAllowedIsRefused() {
        #expect(ActivityLists.conflict(blocking: [.site(domain: "overleaf.com")], allowed: allowed) == .site(domain: "overleaf.com"))
        #expect(ActivityLists.conflict(blocking: [.app(bundleID: "com.apple.finder", name: "Finder")], allowed: allowed)
            == .app(bundleID: "com.apple.finder", name: "Finder"))
        #expect(ActivityLists.conflict(blocking: [.site(domain: "youtube.com")], allowed: allowed) == nil)
    }

    @Test func allowingSomethingBlockedIsRefused() {
        #expect(ActivityLists.conflict(allowing: .site(domain: "instagram.com"), rules: rules) == .site(domain: "instagram.com"))
        #expect(ActivityLists.conflict(allowing: .site(domain: "scholar.google.com"), rules: rules) == nil)
    }

    // Review of PR #39: a blocked subdomain of an allowed site, or the
    // reverse, is the same contradiction.
    @Test func subdomainsOverlapEitherWay() {
        #expect(ActivityLists.conflict(blocking: [.site(domain: "cdn.overleaf.com")], allowed: allowed) == .site(domain: "overleaf.com"))
        #expect(ActivityLists.conflict(allowing: .site(domain: "www2.instagram.com"), rules: rules) == .site(domain: "instagram.com"))
        let blockedSub = [BlockRuleSet(id: 8, targets: [.site(domain: "cdn.overleaf.com")], activation: .always)]
        #expect(ActivityLists.conflict(allowing: .site(domain: "overleaf.com"), rules: blockedSub) == .site(domain: "cdn.overleaf.com"))
        #expect(ActivityLists.conflict(blocking: [.site(domain: "notoverleaf.com")], allowed: allowed) == nil)
    }

    @Test func appsMatchByBundleIDWhateverTheirName() {
        #expect(ActivityLists.conflict(blocking: [.app(bundleID: "com.apple.finder", name: "Finder 2")], allowed: allowed) != nil)
    }
}
