import Foundation
import Testing
@testable import FocusPilotCore

/// #70: the redesign's colors (docs/design/redesign-2026-11, Main and
/// MainDark), in one place, for light, dark and Increased Contrast.
@Suite("Palette")
struct PaletteTests {
    @Test(arguments: [
        (Palette.Token.window, "#ffffff", "#1c1c1e"),
        (.sidebar, "#f3f3f5", "#232326"),
        (.sidebarSelection, "#dedee3", "#3a3a40"),
        (.sidebarBorder, "#dcdce0", "#38383d"),
        (.separator, "#e5e5ea", "#38383d"),
        (.inspector, "#fafafa", "#202023"),
        (.text, "#1d1d1f", "#f2f2f4"),
        (.secondaryText, "#6e6e73", "#a1a1a8"),
        (.footerText, "#3a3a3c", "#c7c7cc"),
        (.accent, "#0b63ce", "#2a74d6"),
        (.nowTint, "#f3f6fb", "#1f2a3c"),
        (.nowBorder, "#d9e3f3", "#2f4262"),
        (.nowLabel, "#3b5b8c", "#8db4ec"),
        (.selectedRow, "#eef2f8", "#2b2f38"),
        (.badge, "#6e6e73", "#b0b0b6"),
        (.badgeText, "#ffffff", "#1c1c1e"),
        (.buttonBackground, "#ffffff", "#2c2c30"),
        (.buttonBorder, "#d1d1d6", "#4a4a50"),
        (.green, "#1f9d55", "#1f9d55"),
        (.amber, "#c77d00", "#c77d00"),
        (.greenText, "#1f6b3a", "#7fd79c"),
    ])
    func eachTokenIsTheBoardsColor(token: Palette.Token, light: String, dark: String) {
        #expect(Palette.color(token, dark: false).hex == light)
        #expect(Palette.color(token, dark: true).hex == dark)
    }

    // Text on every surface it sits on reads at WCAG AA (4.5:1), and at 7:1
    // with Increased Contrast.
    @Test(arguments: [false, true])
    func textIsReadableOnItsSurfaces(dark: Bool) {
        let pairs: [(Palette.Token, Palette.Token)] = [
            (.text, .window), (.text, .sidebar), (.text, .sidebarSelection), (.text, .selectedRow), (.text, .nowTint),
            (.secondaryText, .window), (.secondaryText, .sidebar), (.footerText, .sidebar), (.badgeText, .badge),
        ]
        for (text, surface) in pairs {
            let normal = Palette.color(text, dark: dark).contrast(with: Palette.color(surface, dark: dark))
            let increased = Palette.color(text, dark: dark, increasedContrast: true)
                .contrast(with: Palette.color(surface, dark: dark, increasedContrast: true))
            #expect(normal >= 4.5, "\(text) on \(surface): \(normal)")
            #expect(increased >= 7, "\(text) on \(surface) with Increased Contrast: \(increased)")
        }
    }

    @Test func increasedContrastDarkensBordersAndSelection() {
        for token in [Palette.Token.separator, .sidebarBorder, .buttonBorder, .sidebarSelection] {
            let window = Palette.color(.window, dark: false)
            #expect(Palette.color(token, dark: false, increasedContrast: true).contrast(with: window)
                > Palette.color(token, dark: false).contrast(with: window))
        }
    }
}

@Suite("Sidebar footer")
struct SidebarFooterTests {
    private func chrome(incognito: Bool = true) -> ChromeProfileStatus {
        ChromeProfileStatus(profileID: "4F5CE721-0000-4000-8000-00000000000A", state: .acknowledged(revision: 9),
                            incognitoAllowed: incognito, allSitesAccess: true, missingObservations: 0)
    }

    // #70: one line, "Chrome protected", or the same line with the real state.
    @Test func itIsOneLineWithTheRealState() {
        let protected = BrowserProtection(profiles: [chrome()], chromeRunning: true, confirmedSinceStart: true,
                                          inSession: false, front: nil)
        let missing = BrowserProtection(profiles: [], chromeRunning: true, confirmedSinceStart: true, inSession: false, front: nil)
        let incognito = BrowserProtection(profiles: [chrome(incognito: false)], chromeRunning: true, confirmedSinceStart: true,
                                          inSession: false, front: nil)
        let closed = BrowserProtection(profiles: [chrome()], chromeRunning: false, confirmedSinceStart: true,
                                       inSession: false, front: nil)

        #expect([protected, missing, incognito, closed].map(\.footer)
            == ["Chrome protected", "Chrome not connected", "Incognito unprotected", "Chrome not running"])
        // Review of #77: the footer fits the sidebar; the full line is its tooltip.
        #expect(SidebarFooter(protection: incognito, observing: false).help == "Chrome protected · Incognito unprotected")
        #expect([protected, missing, incognito, closed].allSatisfy { $0.footer.count <= 24 })
        #expect(SidebarFooter(protection: protected, observing: false).tone == .green)
        #expect(SidebarFooter(protection: missing, observing: false).tone == .amber)
        #expect(SidebarFooter(protection: closed, observing: false).tone == .unknown)
        #expect(SidebarFooter(protection: protected, observing: true)
            == SidebarFooter(text: "Observing · nothing blocked", tone: .unknown, help: "Observing · nothing blocked"))
    }

    // Review of #77: arrow keys move through the sidebar in its order, and stop at the ends.
    @Test func arrowKeysMoveThroughTheSidebar() {
        #expect(PlanningPage.allCases == [.today, .inFlight, .projects, .review, .settings])
        #expect(PlanningPage.today.moved(by: 1) == .inFlight)
        #expect(PlanningPage.review.moved(by: -1) == .projects)
        #expect(PlanningPage.today.moved(by: -1) == .today)
        #expect(PlanningPage.settings.moved(by: 1) == .settings)
    }

    @Test func badgesHideAtZero() {
        #expect(SidebarBadge.text(0) == nil)
        #expect(SidebarBadge.text(2) == "2")
        #expect(SidebarBadge.text(120) == "99+")
    }

    @Test func todayShowsTheFullDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = bogota
        #expect(PageHeader.todayDate(wednesdayMorningInBogota, calendar: calendar) == "Wednesday 14 October")
    }
}
