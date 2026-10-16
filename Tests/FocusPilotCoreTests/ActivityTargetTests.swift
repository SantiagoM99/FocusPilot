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
    ])
    func typedSitesBecomeDomains(typed: String, domain: String) {
        #expect(SiteDomain.normalized(typed) == domain)
    }

    @Test(arguments: ["", "   ", "instagram", "not a site", "-bad.com", "bad-.com", "exa_mple.com", "ñandú.com", "localhost", "https://"])
    func textThatIsNotADomainIsRejected(typed: String) {
        #expect(SiteDomain.normalized(typed) == nil)
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

    @Test func appsMatchByBundleIDWhateverTheirName() {
        #expect(ActivityLists.conflict(blocking: [.app(bundleID: "com.apple.finder", name: "Finder 2")], allowed: allowed) != nil)
    }
}
