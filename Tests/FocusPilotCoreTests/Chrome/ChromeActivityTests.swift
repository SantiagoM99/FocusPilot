import Foundation
import Testing
@testable import FocusPilotCore

/// #21: while observing, the extension reports its front tab's domain; the
/// host hands it to the app through an inbox, never the diagnostic log.
@Suite("Chrome front-tab activity")
struct ChromeActivityTests {
    private func harness(observing: Bool) async throws -> HostHarness {
        let harness = try HostHarness()
        let policy = CompiledPolicy(revision: 1, effectiveAt: harness.clock.now,
                                    rules: PolicyCompiler.compile(rules: [], allowed: [], session: nil))
        await ChromePolicyMailbox(location: harness.location)
            .publish(PolicyDelivery(policy: policy, focus: nil, observe: observing ? true : nil))
        harness.hello()
        return harness
    }

    private func inbox(_ harness: HostHarness) -> ChromeActivityInbox {
        ChromeActivityInbox(location: harness.location)
    }

    private func logText(_ harness: HostHarness) -> String {
        let log = harness.location.chromeProfilesDirectory.appending(path: HostHarness.profile + ".log.jsonl")
        return (try? String(contentsOf: log, encoding: .utf8)) ?? ""
    }

    @Test func whileObservingTheFrontTabsDomainReachesTheInboxAndIsAcknowledged() async throws {
        let harness = try await harness(observing: true)

        harness.observe(1, "tab-front", ["domain": "github.com"])
        harness.observe(2, "tab-front", ["domain": NSNull()])

        #expect(inbox(harness).drain(now: harness.clock.now) == [
            ChromeTabReport(domain: "github.com", at: instant("2026-10-14T15:00:00Z")),
            ChromeTabReport(domain: nil, at: instant("2026-10-14T15:00:00Z")),
        ])
        #expect(harness.sent("ack").compactMap { $0["seq"] as? Int } == [1, 2])
        #expect(!logText(harness).contains("github.com"), "Domains stay out of the diagnostic log")
    }

    @Test func drainingEmptiesTheInbox() async throws {
        let harness = try await harness(observing: true)
        harness.observe(1, "tab-front", ["domain": "github.com"])

        _ = inbox(harness).drain(now: harness.clock.now)

        #expect(inbox(harness).drain(now: harness.clock.now).isEmpty)
    }

    @Test func withoutObserveModeNothingIsKeptButItIsStillAcknowledged() async throws {
        let harness = try await harness(observing: false)

        harness.observe(1, "tab-front", ["domain": "github.com"])

        #expect(inbox(harness).drain(now: harness.clock.now).isEmpty)
        #expect(harness.sent("ack").compactMap { $0["seq"] as? Int } == [1])
        #expect(!logText(harness).contains("github.com"))
    }

    // Nothing reads the inbox while the app is quit, so nothing is kept.
    @Test func withTheAppQuitNothingIsKept() async throws {
        let harness = try await harness(observing: true)
        harness.appRunning.withLock { $0 = false }

        harness.observe(1, "tab-front", ["domain": "github.com"])

        #expect(inbox(harness).drain(now: harness.clock.now).isEmpty)
    }

    // Only a domain is ever stored, whatever the extension sends.
    @Test func aReportIsCutDownToItsDomain() async throws {
        let harness = try await harness(observing: true)

        harness.observe(1, "tab-front", ["domain": "https://www.GitHub.com/owner/repo?tab=1", "url": "https://github.com/x"])
        harness.observe(2, "tab-front", ["domain": "not a domain"])

        let raw = try String(contentsOf: harness.location.chromeDirectory.appending(path: "activity.jsonl"), encoding: .utf8)
        #expect(!raw.contains("repo") && !raw.contains("/x"))
        #expect(inbox(harness).drain(now: harness.clock.now).map(\.domain) == ["github.com", nil])
    }

    // The extension reads `observe === true` (observe.test.mjs).
    @Test func theDeliveryNamesObserveOnlyWhileObserving() throws {
        let policy = CompiledPolicy(revision: 1, effectiveAt: wednesdayMorningInBogota,
                                    rules: PolicyCompiler.compile(rules: [], allowed: [], session: nil))
        let encode = { (observe: Bool?) in
            try JSONSerialization.jsonObject(with: CompiledPolicy.encoder().encode(
                PolicyDelivery(policy: policy, focus: nil, observe: observe))) as? [String: Any]
        }

        #expect(try encode(true)?["observe"] as? Bool == true)
        #expect(try encode(nil)?.keys.contains("observe") == false)
    }

    @Test func reportsOlderThanADayAreDropped() async throws {
        let harness = try await harness(observing: true)
        harness.observe(1, "tab-front", ["domain": "github.com"])

        #expect(inbox(harness).drain(now: instant("2026-10-15T15:00:01Z")).isEmpty)
    }
}
