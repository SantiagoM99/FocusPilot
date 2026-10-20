import Foundation
import Testing
@testable import FocusPilotCore

// Owner decision (0003, 2026-10-17): during a strict session, weakening a
// rule needs the same confirmation and wait as ending early.
@Suite("What weakens a rule")
struct RuleWeakeningTests {
    private let instagram = ActivityTarget.site(domain: "instagram.com")
    private let youtube = ActivityTarget.site(domain: "youtube.com")

    private func schedule(_ days: Set<Weekday>, _ from: Int, _ to: Int, _ zone: TimeZone = bogota) -> RuleActivation {
        .schedule(WeeklySchedule(days: days, from: ClockTime(from, 0), to: ClockTime(to, 0), timeZone: zone))
    }

    private func weakens(_ old: RuleActivation, _ new: RuleActivation, targets: [ActivityTarget]? = nil) -> Bool {
        RuleStrength.weakens(BlockRuleSet(id: 1, targets: [instagram], activation: old),
                             to: BlockRuleSet(id: 1, targets: targets ?? [instagram], activation: new))
    }

    @Test func removingATargetWeakensAddingOneDoesNot() {
        #expect(weakens(.always, .always, targets: []))
        #expect(!weakens(.always, .always, targets: [instagram, youtube]))
        #expect(weakens(.always, .always, targets: [.site(domain: "www.instagram.com")]))
    }

    @Test(arguments: [
        (RuleActivation.always, RuleActivation.sessionOnly, true),
        (.sessionOnly, .always, false),
        (.always, .schedule(WeeklySchedule(days: [.mon], from: ClockTime(8, 0), to: ClockTime(18, 0), timeZone: bogota)), true),
        (.schedule(WeeklySchedule(days: [.mon], from: ClockTime(8, 0), to: ClockTime(18, 0), timeZone: bogota)), .always, false),
        (.sessionOnly, .schedule(WeeklySchedule(days: [.mon], from: ClockTime(8, 0), to: ClockTime(18, 0), timeZone: bogota)), true),
        (.schedule(WeeklySchedule(days: [.mon], from: ClockTime(8, 0), to: ClockTime(18, 0), timeZone: bogota)), .sessionOnly, true),
    ])
    func activationChanges(old: RuleActivation, new: RuleActivation, weaker: Bool) {
        #expect(weakens(old, new) == weaker)
    }

    @Test func schedulesWeakenWhenTheyCoverLess() {
        let workdays = schedule([.mon, .tue, .wed, .thu, .fri], 8, 18)
        #expect(!weakens(workdays, workdays))
        #expect(!weakens(workdays, schedule(Set(Weekday.allCases), 8, 18)))
        #expect(!weakens(workdays, schedule([.mon, .tue, .wed, .thu, .fri], 7, 20)))
        #expect(weakens(workdays, schedule([.mon, .tue], 8, 18)))
        #expect(weakens(workdays, schedule([.mon, .tue, .wed, .thu, .fri], 9, 18)))
        #expect(weakens(workdays, schedule([.mon, .tue, .wed, .thu, .fri], 8, 18, newYork)))
    }

    @Test func overnightSchedulesOnlyStayEqualOrGainDays() {
        let nights = schedule([.fri], 22, 2)
        #expect(!weakens(nights, nights))
        #expect(!weakens(nights, schedule([.fri, .sat], 22, 2)))
        #expect(weakens(nights, schedule([.fri], 23, 2)))
    }
}

@Suite("Weakening rules during a strict session")
struct StrictRuleWaitTests {
    private let youtube = BlockRuleSet(targets: [.site(domain: "youtube.com")], activation: .sessionOnly)

    /// A strict session running with one saved session-only rule.
    private func strictFixture() async throws -> (SessionFixture, BlockRuleSet) {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.saveRuleSet(youtube)
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .strict)
        return (fixture, try #require(await fixture.coordinator.ruleSets().first))
    }

    @Test func deletingFirstAsksForConfirmationAndChangesNothing() async throws {
        let (fixture, rule) = try await strictFixture()
        let published = await fixture.publisher.published.count

        #expect(try await fixture.coordinator.deleteRuleSet(rule.id!) == .needsConfirmation)
        #expect(try await fixture.coordinator.ruleSets() == [rule])
        #expect(await fixture.publisher.published.count == published)
        #expect(await fixture.coordinator.snapshot().pendingRuleEdit == nil)
    }

    @Test func confirmingStartsTheWaitAndKeepsTheRule() async throws {
        let (fixture, rule) = try await strictFixture()

        let result = try await fixture.coordinator.deleteRuleSet(rule.id!, confirmed: true)

        let availableAt = fixture.clock.now.addingTimeInterval(StrictEarlyEnd.wait)
        #expect(result == .waitUntil(availableAt))
        #expect(try await fixture.coordinator.ruleSets() == [rule])
        #expect(await fixture.coordinator.snapshot().pendingRuleEdit == PendingRuleEdit(edit: .delete(rule.id!), availableAt: availableAt, expiresAt: availableAt.addingTimeInterval(StrictEarlyEnd.applyWindow)))
        fixture.advance(seconds: 30)
        #expect(try await fixture.coordinator.deleteRuleSet(rule.id!) == .waitUntil(availableAt))
    }

    @Test func afterTheWaitTheChangeApplies() async throws {
        let (fixture, rule) = try await strictFixture()
        _ = try await fixture.coordinator.deleteRuleSet(rule.id!, confirmed: true)
        fixture.advance(minutes: 1)

        #expect(try await fixture.coordinator.deleteRuleSet(rule.id!) == .saved)
        #expect(try await fixture.coordinator.ruleSets().isEmpty)
        #expect(await fixture.coordinator.snapshot().pendingRuleEdit == nil)
    }

    @Test func movingTheWallClockForwardDoesNotSkipTheWait() async throws {
        let (fixture, rule) = try await strictFixture()
        _ = try await fixture.coordinator.deleteRuleSet(rule.id!, confirmed: true)
        fixture.advance(seconds: 10)
        fixture.clock.set(fixture.clock.now.addingTimeInterval(5 * 60))

        #expect(try await fixture.coordinator.deleteRuleSet(rule.id!) == .waitUntil(fixture.clock.now.addingTimeInterval(50)))
    }

    @Test func looseningTheActivationWaitsToo() async throws {
        let (fixture, _) = try await strictFixture()
        var always = BlockRuleSet(targets: [.site(domain: "instagram.com")], activation: .always)
        try await fixture.coordinator.saveRuleSet(always)
        always = try #require(await fixture.coordinator.ruleSets().last)
        always.activation = .sessionOnly

        #expect(try await fixture.coordinator.saveRuleSet(always) == .needsConfirmation)
        #expect(try await fixture.coordinator.saveRuleSet(always, confirmed: true) == .waitUntil(fixture.clock.now.addingTimeInterval(StrictEarlyEnd.wait)))
        fixture.advance(minutes: 1)
        #expect(try await fixture.coordinator.saveRuleSet(always) == .saved)
        #expect(try await fixture.coordinator.ruleSets().last?.activation == .sessionOnly)
    }

    @Test func addingOrTighteningStaysImmediate() async throws {
        let (fixture, rule) = try await strictFixture()
        var tighter = rule
        tighter.activation = .always
        tighter.targets.append(.site(domain: "vimeo.com"))

        #expect(try await fixture.coordinator.saveRuleSet(BlockRuleSet(targets: [.site(domain: "x.com")], activation: .always)) == .saved)
        #expect(try await fixture.coordinator.saveRuleSet(tighter) == .saved)
    }

    @Test func anotherWeakeningNeedsItsOwnConfirmation() async throws {
        let (fixture, rule) = try await strictFixture()
        try await fixture.coordinator.saveRuleSet(BlockRuleSet(targets: [.site(domain: "x.com")], activation: .always))
        let other = try #require(await fixture.coordinator.ruleSets().last)
        _ = try await fixture.coordinator.deleteRuleSet(rule.id!, confirmed: true)
        fixture.advance(minutes: 1)

        #expect(try await fixture.coordinator.deleteRuleSet(other.id!) == .needsConfirmation)
    }

    // Review of PR #39: the repro. A finished wait must not apply over a
    // tightening made in between, nor undo it.
    @Test func aWaitedEditCannotUndoATighteningMadeMeanwhile() async throws {
        let (fixture, rule) = try await strictFixture()
        var both = rule
        both.targets.append(.site(domain: "instagram.com"))
        try await fixture.coordinator.saveRuleSet(both)
        both = try #require(await fixture.coordinator.ruleSets().first)
        var withoutInstagram = both
        withoutInstagram.targets = [.site(domain: "youtube.com")]
        _ = try await fixture.coordinator.saveRuleSet(withoutInstagram, confirmed: true)
        fixture.advance(minutes: 1)
        var tighter = both
        tighter.targets.append(.site(domain: "x.com"))

        #expect(try await fixture.coordinator.saveRuleSet(tighter) == .saved)
        #expect(await fixture.coordinator.snapshot().pendingRuleEdit == nil)
        await #expect(throws: RuleError.ruleChanged) { try await fixture.coordinator.saveRuleSet(withoutInstagram) }
        #expect(try await fixture.coordinator.ruleSets().first?.targets.count == 3)
    }

    @Test func aWaitedDeleteIsRefusedIfTheRuleChanged() async throws {
        let (fixture, rule) = try await strictFixture()
        _ = try await fixture.coordinator.deleteRuleSet(rule.id!, confirmed: true)
        fixture.advance(minutes: 1)
        // Changed outside the coordinator, e.g. by the CLI later.
        var tighter = rule
        tighter.activation = .always
        try await TaskRepository(location: fixture.location).save(tighter)

        await #expect(throws: RuleError.ruleChanged) { try await fixture.coordinator.deleteRuleSet(rule.id!) }
        #expect(try await fixture.coordinator.ruleSets().count == 1)
    }

    @Test func anyOtherEditClearsTheWait() async throws {
        let (fixture, rule) = try await strictFixture()
        _ = try await fixture.coordinator.deleteRuleSet(rule.id!, confirmed: true)

        try await fixture.coordinator.saveRuleSet(BlockRuleSet(targets: [.site(domain: "x.com")], activation: .always))

        #expect(await fixture.coordinator.snapshot().pendingRuleEdit == nil)
        fixture.advance(minutes: 1)
        #expect(try await fixture.coordinator.deleteRuleSet(rule.id!) == .needsConfirmation)
    }

    @Test func aFinishedWaitExpiresIfNotApplied() async throws {
        let (fixture, rule) = try await strictFixture()
        _ = try await fixture.coordinator.deleteRuleSet(rule.id!, confirmed: true)
        let pending = try #require(await fixture.coordinator.snapshot().pendingRuleEdit)
        #expect(pending.expiresAt == pending.availableAt.addingTimeInterval(StrictEarlyEnd.applyWindow))

        fixture.advance(seconds: StrictEarlyEnd.wait + StrictEarlyEnd.applyWindow + 1)

        #expect(await fixture.coordinator.snapshot().pendingRuleEdit == nil)
        #expect(try await fixture.coordinator.deleteRuleSet(rule.id!) == .needsConfirmation)
        #expect(try await fixture.coordinator.ruleSets() == [rule])
    }

    @Test func aFinishedWaitStillAppliesWithinItsWindow() async throws {
        let (fixture, rule) = try await strictFixture()
        _ = try await fixture.coordinator.deleteRuleSet(rule.id!, confirmed: true)
        fixture.advance(seconds: StrictEarlyEnd.wait + StrictEarlyEnd.applyWindow - 1)

        #expect(try await fixture.coordinator.deleteRuleSet(rule.id!) == .saved)
    }

    @Test func cancellingClearsTheWait() async throws {
        let (fixture, rule) = try await strictFixture()
        _ = try await fixture.coordinator.deleteRuleSet(rule.id!, confirmed: true)

        await fixture.coordinator.cancelRuleEdit()

        #expect(await fixture.coordinator.snapshot().pendingRuleEdit == nil)
        #expect(try await fixture.coordinator.deleteRuleSet(rule.id!) == .needsConfirmation)
    }

    @Test func strictPausesStillWait() async throws {
        let (fixture, rule) = try await strictFixture()
        try await fixture.coordinator.pause()

        #expect(try await fixture.coordinator.deleteRuleSet(rule.id!) == .needsConfirmation)
    }

    @Test func normalSessionsAndNoSessionChangeAtOnce() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.saveRuleSet(youtube)
        let rule = try #require(await fixture.coordinator.ruleSets().first)
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)

        #expect(try await fixture.coordinator.deleteRuleSet(rule.id!) == .saved)
    }

    @Test func endingTheSessionDropsTheWait() async throws {
        let (fixture, rule) = try await strictFixture()
        _ = try await fixture.coordinator.deleteRuleSet(rule.id!, confirmed: true)
        fixture.advance(minutes: 26)
        try await fixture.coordinator.reconcile()

        #expect(await fixture.coordinator.snapshot().pendingRuleEdit == nil)
        #expect(try await fixture.coordinator.deleteRuleSet(rule.id!) == .saved)
    }
}

@Suite("Published policy order")
struct PublishedPolicyOrderTests {
    // Review of PR #39: an interleaved edit must not move the shown policy back.
    @Test func anOlderRevisionNeverReplacesANewerOne() async throws {
        let fixture = try await SessionFixture()
        let inputs = PolicyInputs(rules: [], allowed: [])

        await fixture.coordinator.publish(revision: 5, inputs: inputs, session: nil, at: fixture.clock.now)
        await fixture.coordinator.publish(revision: 3, inputs: inputs, session: nil, at: fixture.clock.now)

        #expect(await fixture.coordinator.snapshot().policy?.revision == 5)
    }
}

@Suite("Rule edit text")
struct RuleEditTextTests {
    private let rules = [BlockRuleSet(id: 4, targets: [.site(domain: "youtube.com"), .site(domain: "vimeo.com")], activation: .sessionOnly)]

    @Test func namesTheRuleBeingChanged() {
        #expect(RuleText.title(.delete(4), rules: rules) == "Remove the rule for youtube.com, vimeo.com?")
        #expect(RuleText.title(.save(rules[0]), rules: rules) == "Loosen the rule for youtube.com, vimeo.com?")
        #expect(RuleText.title(.delete(9), rules: rules) == "Remove this rule?")
    }

    @Test func pagesTypedInTheEditorAreExplained() {
        #expect(RuleText.wholeDomainNote("https://www.youtube.com/watch?v=1") == "Blocks all of youtube.com, not only this page.")
        #expect(RuleText.wholeDomainNote("youtube.com") == nil)
    }
}

@Suite("Strict wait text")
struct StrictWaitTextTests {
    @Test func countdownAndWaitLength() {
        let now = wednesdayMorningInBogota
        #expect(RuleText.applyCountdown(availableAt: now.addingTimeInterval(45), now: now) == "You can apply it in 0:45")
        #expect(RuleText.applyCountdown(availableAt: now, now: now) == "You can apply it now")
        #expect(StrictEarlyEnd.waitText == "1 minute")
    }
}
