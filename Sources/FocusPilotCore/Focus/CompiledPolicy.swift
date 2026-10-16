import Foundation

/// Domains and app bundle IDs, sorted and without duplicates.
public struct PolicyTargets: Hashable, Codable, Sendable {
    public var domains: [String]
    public var apps: [String]

    public init(domains: [String] = [], apps: [String] = []) {
        self.domains = domains
        self.apps = apps
    }

    init(_ targets: some Sequence<ActivityTarget>) {
        var domains = Set<String>(), apps = Set<String>()
        for target in targets {
            switch target {
            case .site(let domain): domains.insert(domain)
            case .app(let bundleID, _): apps.insert(bundleID)
            case .tool: break
            }
        }
        self.init(domains: domains.sorted(), apps: apps.sorted())
    }
}

/// Targets blocked inside a schedule's windows.
public struct ScheduledBlock: Hashable, Codable, Sendable {
    public var schedule: WeeklySchedule
    public var targets: PolicyTargets
}

/// The session's part: its absolute end (decision 0003) and the
/// session-only targets. Present only while session rules apply or will
/// resume after a normal break.
public struct SessionBlock: Hashable, Codable, Sendable {
    public var sessionID: UUID
    public var mode: SessionMode
    public var end: Date
    public var resumesAt: Date?
    public var targets: PolicyTargets

    public init(_ session: SessionPolicy, targets: PolicyTargets) {
        sessionID = session.sessionID
        mode = session.mode
        end = session.end
        resumesAt = session.resumesAt
        self.targets = targets
    }
}

/// Allowed entries; check-ins (#21) skip them. Extensions do not block with them.
public struct AllowedTargets: Hashable, Codable, Sendable {
    public var domains: [String]
    public var apps: [String]
    public var tools: [String]

    public init(domains: [String] = [], apps: [String] = [], tools: [String] = []) {
        self.domains = domains
        self.apps = apps
        self.tools = tools
    }
}

/// What the rule sets, allowed list and session amount to, before the
/// coordinator gives it a revision.
public struct PolicyRules: Hashable, Sendable {
    public var always: PolicyTargets
    public var scheduled: [ScheduledBlock]
    public var session: SessionBlock?
    public var allowed: AllowedTargets
    /// SHA-256 of the rules above, hex. Equal rules give equal checksums.
    public var checksum: String
}

/// The policy the extensions and app enforce (design: DATA_AND_MEMORY,
/// CompiledPolicy). FocusCoordinator wraps every publish with a schema
/// version, a revision that only grows (stored in the owner database) and
/// the instant it takes effect, so an extension can reject a stale or
/// out-of-order policy (decision 0003, 2026-10-14; required by #15).
public struct CompiledPolicy: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion = Self.currentSchemaVersion
    public var revision: Int
    public var effectiveAt: Date
    public var checksum: String
    public var always: PolicyTargets
    public var scheduled: [ScheduledBlock]
    /// `nil` means no session rules apply.
    public var session: SessionBlock?
    public var allowed: AllowedTargets

    public init(revision: Int, effectiveAt: Date, rules: PolicyRules) {
        self.revision = revision
        self.effectiveAt = effectiveAt
        checksum = rules.checksum
        always = rules.always
        scheduled = rules.scheduled
        session = rules.session
        allowed = rules.allowed
    }

    /// The JSON the extensions read: sorted keys, UTC ISO 8601 instants.
    public func json(pretty: Bool = false) throws -> Data {
        try Self.encoder(pretty: pretty).encode(self)
    }

    static func encoder(pretty: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted] : [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

/// Delivers policies to the browser extensions. Delivery itself arrives with
/// the extensions (#13, #16); until then the app uses `PolicyNotDelivered`.
public protocol PolicyPublisher: Sendable {
    func publish(_ policy: CompiledPolicy) async
}

/// Tells the owner about a session event, such as reaching the planned end.
public protocol FocusNoticeSink: Sendable {
    func deliver(_ notice: FocusNotice) async
}

/// Keeps nothing: no extension is installed to receive policies yet.
public struct PolicyNotDelivered: PolicyPublisher {
    public init() {}
    public func publish(_ policy: CompiledPolicy) async {}
}

/// Drops notices; the app supplies a sink that shows them.
public struct NoticesIgnored: FocusNoticeSink {
    public init() {}
    public func deliver(_ notice: FocusNotice) async {}
}
