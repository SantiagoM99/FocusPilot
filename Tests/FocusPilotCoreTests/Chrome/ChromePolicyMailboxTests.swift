import Foundation
import Testing
@testable import FocusPilotCore

@Suite("Policy mailbox for Chrome")
struct ChromePolicyMailboxTests {
    private let location: StorageLocation
    private let mailbox: ChromePolicyMailbox

    init() throws {
        location = StorageLocation(directory: try makeTemporaryDirectory())
        mailbox = ChromePolicyMailbox(location: location)
    }

    private func delivery(revision: Int, focus: FocusContext? = nil) -> PolicyDelivery {
        let rules = PolicyCompiler.compile(rules: [BlockRuleSet(id: 1, targets: [.site(domain: "youtube.com")], activation: .always)],
                                           allowed: [], session: nil)
        return PolicyDelivery(policy: CompiledPolicy(revision: revision, effectiveAt: wednesdayMorningInBogota, rules: rules), focus: focus)
    }

    @Test func thePublishedPolicyIsWhatTheHostReads() async throws {
        let sent = delivery(revision: 3, focus: FocusContext(title: "Explain baseline results", nextAction: "Write §4.2", projectTitle: "NLP report"))

        await mailbox.publish(sent)

        #expect(try ChromePolicyMailbox.read(location) == sent)
    }

    @Test func anOlderRevisionNeverReplacesANewerOne() async throws {
        await mailbox.publish(delivery(revision: 5))
        await mailbox.publish(delivery(revision: 4))

        #expect(try ChromePolicyMailbox.read(location)?.policy.revision == 5)
    }

    @Test func nothingPublishedReadsAsNil() throws {
        #expect(try ChromePolicyMailbox.read(location) == nil)
    }

    @Test func theFileIsOnlyReadableByTheOwner() async throws {
        await mailbox.publish(delivery(revision: 1))

        let attributes = try FileManager.default.attributesOfItem(atPath: location.chromePolicyURL.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
    }
}

@Suite("What the coordinator tells Chrome")
struct ChromeFocusContextTests {
    @Test func aSessionPolicyCarriesTheTaskForTheBlockedPage() async throws {
        let fixture = try await SessionFixture()

        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)

        let delivered = try #require(await fixture.publisher.deliveries.last)
        #expect(delivered.focus?.title == "Explain baseline results")
    }

    @Test func withoutSessionRulesThereIsNoTask() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.saveRuleSet(BlockRuleSet(targets: [.site(domain: "youtube.com")], activation: .always))

        #expect(await fixture.publisher.deliveries.last?.focus == nil)
    }
}
