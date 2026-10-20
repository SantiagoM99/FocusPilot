import Foundation
import Testing
@testable import FocusPilotCore

@Suite("Policy compiler")
struct PolicyCompilerTests {
    private let evenings = WeeklySchedule(days: [.mon, .tue], from: ClockTime(19, 0), to: ClockTime(23, 0), timeZone: bogota)
    private let instagram = ActivityTarget.site(domain: "instagram.com")
    private let youtube = ActivityTarget.site(domain: "youtube.com")
    private let tiktok = ActivityTarget.site(domain: "tiktok.com")
    private let instagramApp = ActivityTarget.app(bundleID: "com.burbn.instagram", name: "Instagram")
    private let session = SessionPolicy(sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, mode: .strict,
                                        end: instant("2026-10-14T10:50:00-05:00"))

    private var rules: [BlockRuleSet] {
        [
            BlockRuleSet(id: 1, targets: [instagram, instagramApp], activation: .always),
            BlockRuleSet(id: 2, targets: [youtube], activation: .sessionOnly),
            BlockRuleSet(id: 3, targets: [tiktok], activation: .schedule(evenings)),
        ]
    }
    private let allowed = [
        AllowedActivity(id: 1, name: "Overleaf", target: .site(domain: "overleaf.com"), source: .seeded),
        AllowedActivity(id: 2, name: "Finder", target: .app(bundleID: "com.apple.finder", name: "Finder"), source: .seeded),
        AllowedActivity(id: 3, name: "Herdr", target: .tool(command: "herdr"), source: .seeded),
    ]

    @Test func alwaysOnRulesApplyWithoutASession() {
        let policy = PolicyCompiler.compile(rules: rules, allowed: allowed, session: nil)

        #expect(policy.always == PolicyTargets(domains: ["instagram.com"], apps: ["com.burbn.instagram"]))
        #expect(policy.session == nil)
    }

    @Test func scheduledRulesCarryTheirWindowsForTheExtensionsToEvaluate() {
        let policy = PolicyCompiler.compile(rules: rules, allowed: allowed, session: nil)

        #expect(policy.scheduled == [ScheduledBlock(schedule: evenings, targets: PolicyTargets(domains: ["tiktok.com"], apps: []))])
    }

    @Test func sessionOnlyRulesApplyOnlyWithSessionRules() {
        let policy = PolicyCompiler.compile(rules: rules, allowed: allowed, session: session)

        #expect(policy.session == SessionBlock(session, targets: PolicyTargets(domains: ["youtube.com"], apps: [])))
        #expect(policy.session?.end == session.end)
    }

    @Test func aSessionWithoutSessionOnlyRulesStillCarriesItsEnd() {
        let policy = PolicyCompiler.compile(rules: [], allowed: [], session: session)

        #expect(policy.session == SessionBlock(session, targets: PolicyTargets()))
    }

    @Test func targetsAreSortedAndDeduplicatedAcrossRuleSets() {
        let more = rules + [BlockRuleSet(id: 4, targets: [.site(domain: "facebook.com"), instagram], activation: .always)]

        #expect(PolicyCompiler.compile(rules: more, allowed: [], session: nil).always.domains == ["facebook.com", "instagram.com"])
    }

    @Test func schedulesWithTheSameWindowsMerge() {
        let more = rules + [BlockRuleSet(id: 4, targets: [.site(domain: "reddit.com")], activation: .schedule(evenings))]

        #expect(PolicyCompiler.compile(rules: more, allowed: [], session: nil).scheduled.map(\.targets.domains) == [["reddit.com", "tiktok.com"]])
    }

    @Test func allowedAppsSitesAndToolsAreListed() {
        let policy = PolicyCompiler.compile(rules: [], allowed: allowed, session: nil)

        #expect(policy.allowed == AllowedTargets(domains: ["overleaf.com"], apps: ["com.apple.finder"], tools: ["herdr"]))
    }

    @Test func ruleSetOrderDoesNotChangeTheChecksum() {
        let a = PolicyCompiler.compile(rules: rules, allowed: allowed, session: session)
        let b = PolicyCompiler.compile(rules: rules.reversed(), allowed: allowed.reversed(), session: session)

        #expect(a.checksum == b.checksum)
        #expect(a.checksum.count == 64)
    }

    @Test func anyRuleChangeChangesTheChecksum() {
        let base = PolicyCompiler.compile(rules: rules, allowed: allowed, session: nil).checksum
        var edited = rules
        edited[2].activation = .always

        #expect(PolicyCompiler.compile(rules: edited, allowed: allowed, session: nil).checksum != base)
        #expect(PolicyCompiler.compile(rules: rules, allowed: [], session: nil).checksum != base)
        #expect(PolicyCompiler.compile(rules: rules, allowed: allowed, session: session).checksum != base)
    }

    @Test func wrappingAddsSchemaRevisionAndEffectiveTime() {
        let rules = PolicyCompiler.compile(rules: rules, allowed: allowed, session: session)

        let policy = CompiledPolicy(revision: 41, effectiveAt: wednesdayMorningInBogota, rules: rules)

        #expect(policy.schemaVersion == CompiledPolicy.currentSchemaVersion)
        #expect(policy.revision == 41)
        #expect(policy.checksum == rules.checksum)
        #expect(policy.session?.end == session.end)
    }

    // The extensions read this JSON; changing its shape needs a schema bump.
    @Test func jsonShapeForTheExtensions() throws {
        let compiled = PolicyCompiler.compile(rules: rules, allowed: [allowed[0]], session: session)
        let policy = CompiledPolicy(revision: 41, effectiveAt: instant("2026-10-14T10:00:00-05:00"), rules: compiled)

        let json = String(decoding: try policy.json(), as: UTF8.self)

        #expect(json == """
            {"allowed":{"apps":[],"domains":["overleaf.com"],"tools":[]},\
            "always":{"apps":["com.burbn.instagram"],"domains":["instagram.com"]},\
            "checksum":"\(compiled.checksum)","effectiveAt":"2026-10-14T15:00:00Z","revision":41,\
            "scheduled":[{"schedule":{"days":["mon","tue"],"end":"23:00","start":"19:00","timeZone":"America/Bogota"},\
            "targets":{"apps":[],"domains":["tiktok.com"]}}],\
            "schemaVersion":1,\
            "session":{"end":"2026-10-14T15:50:00Z","mode":"strict","sessionID":"00000000-0000-0000-0000-000000000001",\
            "targets":{"apps":[],"domains":["youtube.com"]}}}
            """)
    }
}
