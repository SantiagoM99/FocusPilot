import Foundation
import Testing
@testable import FocusPilotCore

/// The extension's node tests evaluate `Tests/ChromeExtension/fixtures/delivery.json`;
/// this pins that file to what the app actually writes, so the two sides
/// cannot drift apart unnoticed.
@Suite("Chrome policy contract")
struct ChromeContractTests {
    static let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "ChromeExtension/fixtures/delivery.json")

    static var delivery: PolicyDelivery {
        let evenings = WeeklySchedule(days: [.mon, .tue], from: ClockTime(19, 0), to: ClockTime(23, 0), timeZone: bogota)
        let session = SessionPolicy(sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, mode: .strict,
                                    end: instant("2026-10-14T10:50:00-05:00"))
        let rules = [
            BlockRuleSet(id: 1, targets: [.site(domain: "instagram.com")], activation: .always),
            BlockRuleSet(id: 2, targets: [.site(domain: "youtube.com")], activation: .sessionOnly),
            BlockRuleSet(id: 3, targets: [.site(domain: "tiktok.com")], activation: .schedule(evenings)),
        ]
        let compiled = PolicyCompiler.compile(rules: rules, allowed: [], session: session)
        return PolicyDelivery(policy: CompiledPolicy(revision: 41, effectiveAt: instant("2026-10-14T10:00:00-05:00"), rules: compiled),
                              focus: FocusContext(title: "Explain baseline results", nextAction: "Write §4.2", projectTitle: "NLP report"),
                              source: "7D5E0C1A-0000-4000-8000-000000000041")
    }

    @Test func theExtensionsFixtureIsWhatTheAppWrites() throws {
        let written = try CompiledPolicy.encoder().encode(Self.delivery)
        let fixture = try Data(contentsOf: Self.fixture)

        #expect(String(decoding: written, as: UTF8.self) == String(decoding: fixture, as: UTF8.self).trimmingCharacters(in: .newlines))
    }
}
