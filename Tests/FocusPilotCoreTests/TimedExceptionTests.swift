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
        try await fixture.coordinator.saveRuleSet(BlockRuleSet(targets: [.site(domain: "youtube.com")], activation: .always))

        _ = try await fixture.coordinator.requestException(.page(url: "https://www.youtube.com/watch?v=3kqW9M"), duration: 20 * 60)
        _ = try await fixture.coordinator.requestException(.site(domain: "youtube.com"), duration: 5 * 60)

        #expect(await fixture.publisher.published.last?.exceptions.count == 2)
    }

    @Test func onlyTheOfferedDurationsAreGranted() async throws {
        let fixture = try await SessionFixture()

        for minutes in [0.0, -5, 7, 15, 60] {
            await #expect(throws: ExceptionError.unsupportedDuration) {
                try await fixture.coordinator.requestException(instagram, duration: minutes * 60)
            }
        }
        #expect(await fixture.publisher.published.isEmpty)
        for minutes in [5.0, 10, 20] {
            guard case .granted = try await fixture.coordinator.requestException(instagram, duration: minutes * 60) else {
                Issue.record("\(minutes) min was not granted")
                continue
            }
        }
    }

    @Test func aStrictSessionChecksTheDurationBeforeAskingToConfirm() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.startSession(duration: 50 * 60, mode: .strict)

        await #expect(throws: ExceptionError.unsupportedDuration) {
            try await fixture.coordinator.requestException(instagram, duration: 45 * 60, reason: "Lab chat", confirmed: true)
        }
        #expect(await fixture.coordinator.snapshot().pendingException == nil)
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

/// Owner decision 0003, 2026-10-22.
@Suite("Starting a strict session cancels earlier exceptions")
struct StrictStartExceptionTests {
    private let youtube = ExceptionScope.site(domain: "youtube.com")

    @Test func appAndSiteExceptionsGrantedBeforeAStrictStartAreCancelled() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.saveRuleSet(BlockRuleSet(targets: [.app(bundleID: "com.burbn.instagram", name: "Instagram")], activation: .always))
        try await fixture.coordinator.saveRuleSet(BlockRuleSet(targets: [.site(domain: "youtube.com")], activation: .sessionOnly))
        _ = try await fixture.coordinator.requestException(instagram, duration: 20 * 60)
        _ = try await fixture.coordinator.requestException(youtube, duration: 20 * 60)
        fixture.advance(minutes: 1)

        try await fixture.coordinator.startSession(duration: 50 * 60, mode: .strict)

        let policy = try #require(await fixture.publisher.published.last)
        #expect(policy.session?.mode == .strict)
        #expect(policy.exceptions.isEmpty)
        #expect(AppBlocking.verdict(for: "com.burbn.instagram", policy: policy, at: fixture.clock.now) == .hide(.always))
        #expect(await fixture.coordinator.snapshot().nextDeadline == policy.session?.end)
    }

    @Test func theyStayCancelledAfterARelaunchAndTheSessionEnding() async throws {
        let fixture = try await SessionFixture()
        _ = try await fixture.coordinator.requestException(instagram, duration: 20 * 60)
        try await fixture.coordinator.startSession(duration: 5 * 60, mode: .strict)
        fixture.advance(minutes: 6)

        let relaunched = try fixture.relaunched()
        try await relaunched.launch()

        #expect(await relaunched.snapshot().activeSession == nil)
        #expect(await relaunched.snapshot().policy?.exceptions == [])
    }

    @Test func aNormalSessionKeepsThem() async throws {
        let fixture = try await SessionFixture()
        _ = try await fixture.coordinator.requestException(instagram, duration: 20 * 60)

        try await fixture.coordinator.startSession(duration: 50 * 60, mode: .normal)

        #expect(await fixture.publisher.published.last?.exceptions.map(\.scope) == [instagram])
    }

    @Test func anExceptionGrantedInsideTheStrictSessionStays() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.startSession(duration: 50 * 60, mode: .strict)
        _ = try await fixture.coordinator.requestException(instagram, duration: 10 * 60, reason: "Lab chat", confirmed: true)
        fixture.advance(seconds: 60)
        _ = try await fixture.coordinator.requestException(instagram, duration: 10 * 60, reason: "Lab chat")

        try await fixture.coordinator.pause()
        try await fixture.coordinator.resume()

        #expect(await fixture.publisher.published.last?.exceptions.map(\.scope) == [instagram])
    }
}
