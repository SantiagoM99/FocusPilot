import Foundation
import Testing
@testable import FocusPilotCore

@MainActor
@Suite("First-launch planning window")
struct FirstLaunchWelcomeTests {
    /// A private defaults domain per test, so tests never read or write the
    /// real app's preferences.
    private let defaults = UserDefaults(suiteName: "FocusPilotTests-\(UUID().uuidString)")!

    @Test func opensThePlanningWindowWhenThereAreNoTasks() {
        let welcome = FirstLaunchWelcome(defaults: defaults)

        #expect(welcome.claimPlanningWindowOpening(hasTasks: false))
    }

    @Test func opensItOnlyOnce() {
        let welcome = FirstLaunchWelcome(defaults: defaults)
        _ = welcome.claimPlanningWindowOpening(hasTasks: false)

        #expect(!FirstLaunchWelcome(defaults: defaults).claimPlanningWindowOpening(hasTasks: false))
    }

    @Test func doesNotOpenItWhenTasksAlreadyExist() {
        let welcome = FirstLaunchWelcome(defaults: defaults)

        #expect(!welcome.claimPlanningWindowOpening(hasTasks: true))
    }
}
