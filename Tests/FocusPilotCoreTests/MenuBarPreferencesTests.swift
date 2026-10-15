import Foundation
import Testing
@testable import FocusPilotCore

@MainActor
@Suite("Menu bar preferences")
struct MenuBarPreferencesTests {
    private let defaults = UserDefaults(suiteName: "FocusPilotTests-\(UUID().uuidString)")!

    @Test func timeLabelIsOffByDefault() {
        #expect(!MenuBarPreferences(defaults: defaults).showsTime)
    }

    @Test func turningTheTimeLabelOnIsRemembered() {
        MenuBarPreferences(defaults: defaults).showsTime = true

        #expect(MenuBarPreferences(defaults: defaults).showsTime)
    }
}
