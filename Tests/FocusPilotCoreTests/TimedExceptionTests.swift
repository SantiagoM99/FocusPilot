import Foundation
import Testing
@testable import FocusPilotCore

private let instagram = ExceptionScope.app(bundleID: "com.burbn.instagram")

@Suite("Timed exceptions through the coordinator")
struct TimedExceptionTests {
    private let blockInstagram = BlockRuleSet(targets: [.app(bundleID: "com.burbn.instagram", name: "Instagram")], activation: .always)

    @Test func outsideAStrictSessionAnExceptionIsGrantedAtOnceAndPublished() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.saveRuleSet(blockInstagram)
        let expiry = fixture.clock.now.addingTimeInterval(10 * 60)

        let outcome = try await fixture.coordinator.requestException(instagram, duration: 10 * 60)

        #expect(outcome == .granted(expiresAt: expiry))
        let policy = try #require(await fixture.publisher.published.last)
        #expect(policy.exceptions == [PolicyException(scope: instagram, expiresAt: expiry)])
        #expect(await fixture.coordinator.snapshot().policy == policy)
        #expect(AppBlocking.verdict(for: "com.burbn.instagram", policy: policy, at: fixture.clock.now) == .allow)
    }

    @Test func aNormalSessionGrantsAtOnceToo() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)

        #expect(try await fixture.coordinator.requestException(instagram, duration: 5 * 60)
            == .granted(expiresAt: fixture.clock.now.addingTimeInterval(5 * 60)))
    }

    @Test func theExpiryIsTheNextDeadlineAndReconcilingThenDropsIt() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.saveRuleSet(blockInstagram)
        _ = try await fixture.coordinator.requestException(instagram, duration: 5 * 60)
        let expiry = fixture.clock.now.addingTimeInterval(5 * 60)
        #expect(await fixture.coordinator.snapshot().nextDeadline == expiry)

        fixture.advance(minutes: 5)
        try await fixture.coordinator.reconcile()

        let policy = try #require(await fixture.publisher.published.last)
        #expect(policy.exceptions.isEmpty)
        #expect(AppBlocking.verdict(for: "com.burbn.instagram", policy: policy, at: fixture.clock.now) == .hide(.always))
        #expect(await fixture.coordinator.snapshot().nextDeadline == nil)
    }

    @Test func anExceptionSurvivesARelaunchButNotItsExpiry() async throws {
        let fixture = try await SessionFixture()
        _ = try await fixture.coordinator.requestException(instagram, duration: 10 * 60)

        let relaunched = try fixture.relaunched()
        try await relaunched.launch()
        #expect(await relaunched.snapshot().policy?.exceptions.map(\.scope) == [instagram])

        fixture.advance(minutes: 11)
        let later = try fixture.relaunched()
        try await later.launch()
        #expect(await later.snapshot().policy?.exceptions == [])
    }

    @Test func sitesAndPagesUseTheSameModel() async throws {
        let fixture = try await SessionFixture()

        _ = try await fixture.coordinator.requestException(.page(url: "https://www.youtube.com/watch?v=3kqW9M"), duration: 20 * 60)
        _ = try await fixture.coordinator.requestException(.site(domain: "youtube.com"), duration: 5 * 60)

        #expect(await fixture.publisher.published.last?.exceptions.count == 2)
    }

    @Test func aNonPositiveDurationIsRefused() async throws {
        let fixture = try await SessionFixture()

        await #expect(throws: ExceptionError.nonPositiveDuration) {
            try await fixture.coordinator.requestException(instagram, duration: 0)
        }
        #expect(await fixture.publisher.published.isEmpty)
    }
}

@Suite("Timed exceptions in a strict session")
struct StrictExceptionTests {
    private func strictFixture() async throws -> SessionFixture {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.startSession(duration: 50 * 60, mode: .strict)
        return fixture
    }

    @Test func theOwnerConfirmsThenWaitsAMinuteBeforeItIsGranted() async throws {
        let fixture = try await strictFixture()
        let published = await fixture.publisher.published.count

        #expect(try await fixture.coordinator.requestException(instagram, duration: 10 * 60, reason: "Reply to the lab") == .needsConfirmation)
        let availableAt = fixture.clock.now.addingTimeInterval(60)
        #expect(try await fixture.coordinator.requestException(instagram, duration: 10 * 60, reason: "Reply to the lab", confirmed: true)
            == .waitUntil(availableAt))
        #expect(await fixture.coordinator.snapshot().pendingException?.availableAt == availableAt)

        fixture.advance(seconds: 30)
        #expect(try await fixture.coordinator.requestException(instagram, duration: 10 * 60, reason: "Reply to the lab")
            == .waitUntil(availableAt))
        #expect(await fixture.publisher.published.count == published)

        fixture.advance(seconds: 30)
        let granted = try await fixture.coordinator.requestException(instagram, duration: 10 * 60, reason: "Reply to the lab")

        // Ten minutes from the grant, not from the request.
        #expect(granted == .granted(expiresAt: fixture.clock.now.addingTimeInterval(10 * 60)))
        #expect(await fixture.publisher.published.last?.exceptions.map(\.scope) == [instagram])
        #expect(await fixture.coordinator.snapshot().pendingException == nil)
    }

    @Test func movingTheMacsClockDoesNotSkipTheWait() async throws {
        let fixture = try await strictFixture()
        _ = try await fixture.coordinator.requestException(instagram, duration: 5 * 60, reason: "Lab chat", confirmed: true)

        fixture.clock.set(fixture.clock.now.addingTimeInterval(3600))

        guard case .waitUntil = try await fixture.coordinator.requestException(instagram, duration: 5 * 60, reason: "Lab chat") else {
            Issue.record("granted before the wait was over")
            return
        }
    }

    @Test func aStrictExceptionNeedsAReason() async throws {
        let fixture = try await strictFixture()

        await #expect(throws: ExceptionError.reasonRequired) {
            try await fixture.coordinator.requestException(instagram, duration: 5 * 60, reason: "  ", confirmed: true)
        }
        #expect(await fixture.coordinator.snapshot().pendingException == nil)
    }

    @Test func aDifferentRequestStartsItsOwnWait() async throws {
        let fixture = try await strictFixture()
        _ = try await fixture.coordinator.requestException(instagram, duration: 5 * 60, reason: "Lab chat", confirmed: true)
        fixture.advance(seconds: 60)

        let other = try await fixture.coordinator.requestException(.app(bundleID: "com.tiktok"), duration: 5 * 60, reason: "Lab chat")

        #expect(other == .needsConfirmation)
    }

    @Test func cancellingOrEndingTheSessionDropsTheWait() async throws {
        let fixture = try await strictFixture()
        _ = try await fixture.coordinator.requestException(instagram, duration: 5 * 60, reason: "Lab chat", confirmed: true)

        await fixture.coordinator.cancelException()
        #expect(await fixture.coordinator.snapshot().pendingException == nil)

        _ = try await fixture.coordinator.requestException(instagram, duration: 5 * 60, reason: "Lab chat", confirmed: true)
        fixture.advance(minutes: 50)
        try await fixture.coordinator.reconcile()
        #expect(await fixture.coordinator.snapshot().pendingException == nil)
    }
}
