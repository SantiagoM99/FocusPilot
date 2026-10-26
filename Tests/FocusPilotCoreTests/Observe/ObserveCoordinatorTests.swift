import Foundation
import Testing
@testable import FocusPilotCore

@Suite("Observe-only through the coordinator")
struct ObserveCoordinatorTests {
    private let rules = [
        BlockRuleSet(targets: [.site(domain: "instagram.com"), .app(bundleID: "com.burbn.instagram", name: "Instagram")],
                     activation: .always),
        BlockRuleSet(targets: [.site(domain: "youtube.com")], activation: .sessionOnly),
    ]

    private func fixture() async throws -> SessionFixture {
        let fixture = try await SessionFixture()
        for rule in rules { try await fixture.coordinator.saveRuleSet(rule) }
        return fixture
    }

    @Test func observingPublishesAPolicyThatBlocksNothingAndAsksChromeToReport() async throws {
        let fixture = try await fixture()

        try await fixture.coordinator.setObserveOnly(true)

        let delivery = try #require(await fixture.publisher.deliveries.last)
        #expect(delivery.observe == true)
        #expect(delivery.policy.always.domains.isEmpty && delivery.policy.always.apps.isEmpty)
        let snapshot = await fixture.coordinator.snapshot()
        #expect(snapshot.isObserveOnly)
        #expect(snapshot.observeSince == fixture.clock.now)
        #expect(AppBlocking.verdict(for: "com.burbn.instagram", policy: snapshot.policy, at: fixture.clock.now) == .allow)
    }

    @Test func sessionsStillRunAndAreTimedButTheirRulesAreNotEnforced() async throws {
        let fixture = try await fixture()
        try await fixture.coordinator.setObserveOnly(true)

        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .strict)

        let delivery = try #require(await fixture.publisher.deliveries.last)
        #expect(delivery.policy.session == nil)
        #expect(delivery.focus == nil)
        #expect(delivery.observe == true)
        #expect(await fixture.coordinator.snapshot().activeSession?.mode == .strict)
    }

    @Test func ruleEditsWhileObservingStillBlockNothing() async throws {
        let fixture = try await fixture()
        try await fixture.coordinator.setObserveOnly(true)

        try await fixture.coordinator.saveRuleSet(BlockRuleSet(targets: [.site(domain: "tiktok.com")], activation: .always))

        #expect(await fixture.publisher.deliveries.last?.policy.always.domains == [])
        #expect(try await fixture.coordinator.ruleSets().count == 3, "The rules are kept for later")
    }

    @Test func turningItOffBlocksWithTheRulesAgainRightAway() async throws {
        let fixture = try await fixture()
        try await fixture.coordinator.setObserveOnly(true)

        try await fixture.coordinator.setObserveOnly(false)

        let delivery = try #require(await fixture.publisher.deliveries.last)
        #expect(delivery.observe == nil)
        #expect(delivery.policy.always.domains == ["instagram.com"])
        #expect(await !fixture.coordinator.snapshot().isObserveOnly)
    }

    // Observing would lift a strict session's blocking at once.
    @Test func itCannotBeTurnedOnDuringAStrictSession() async throws {
        let fixture = try await fixture()
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .strict)

        await #expect(throws: ObserveError.strictSession) { try await fixture.coordinator.setObserveOnly(true) }
        #expect(await fixture.publisher.deliveries.last?.policy.session != nil)
        #expect(await !fixture.coordinator.snapshot().isObserveOnly)
    }

    @Test func itLastsAcrossARelaunch() async throws {
        let fixture = try await fixture()
        try await fixture.coordinator.setObserveOnly(true)

        let relaunched = try fixture.relaunched()
        try await relaunched.launch()

        #expect(await relaunched.snapshot().isObserveOnly)
        #expect(await fixture.publisher.deliveries.last?.observe == true)
        #expect(await fixture.publisher.deliveries.last?.policy.always.domains == [])
    }

    @Test func activityIsRecordedAndReadBackAsEvents() async throws {
        let fixture = try await fixture()
        let event = PilotEvent(kind: .distractionVisit, at: fixture.clock.now, duration: 40, target: "instagram.com")

        try await fixture.coordinator.record(ActivityRecord(events: [event]))

        #expect(try await fixture.coordinator.pilotEvents(since: fixture.clock.now.addingTimeInterval(-60)) == [event])
    }
}
