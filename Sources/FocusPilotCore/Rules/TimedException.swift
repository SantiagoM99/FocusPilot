import Foundation

/// What a timed exception unblocks (DATA_AND_MEMORY, Exception): a whole
/// Mac app, a whole site or one exact page. Sites and pages are granted
/// from the blocked page (#14); apps from the blocked-app panel (#25).
public enum ExceptionScope: Hashable, Codable, Sendable {
    case app(bundleID: String)
    case site(domain: String)
    case page(url: String)

    // Spelled out for the extensions, which switch on "kind":
    // {"kind":"app","bundleID":…}, {"kind":"site","domain":…}, {"kind":"page","url":…}.
    private enum CodingKeys: String, CodingKey {
        case kind, bundleID, domain, url
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "app": self = .app(bundleID: try container.decode(String.self, forKey: .bundleID))
        case "site": self = .site(domain: try container.decode(String.self, forKey: .domain))
        case "page": self = .page(url: try container.decode(String.self, forKey: .url))
        case let kind: throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown scope \(kind)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .app(let bundleID):
            try container.encode("app", forKey: .kind)
            try container.encode(bundleID, forKey: .bundleID)
        case .site(let domain):
            try container.encode("site", forKey: .kind)
            try container.encode(domain, forKey: .domain)
        case .page(let url):
            try container.encode("page", forKey: .kind)
            try container.encode(url, forKey: .url)
        }
    }
}

/// An exception as the policy carries it: its scope and absolute expiry,
/// so whoever enforces it lets it lapse on its own clock.
public struct PolicyException: Hashable, Codable, Sendable {
    public var scope: ExceptionScope
    public var expiresAt: Date

    public init(scope: ExceptionScope, expiresAt: Date) {
        self.scope = scope
        self.expiresAt = expiresAt
    }
}

/// A granted exception as the owner database keeps it (DATA_AND_MEMORY,
/// Exception). Rows stay after they expire; only unexpired ones reach a policy.
public struct TimedException: Hashable, Sendable {
    public var id: Int64?
    public var scope: ExceptionScope
    public var grantedAt: Date
    /// Absolute: sleep, a quit app or a restart never extend it.
    public var expiresAt: Date
    /// The session it was granted in, if any.
    public var sessionID: UUID?
    public var reason: String?

    public init(id: Int64? = nil, scope: ExceptionScope, grantedAt: Date, expiresAt: Date, sessionID: UUID? = nil, reason: String? = nil) {
        self.id = id
        self.scope = scope
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
        self.sessionID = sessionID
        self.reason = reason
    }

    /// The only durations granted, as offered on the blocked page and the
    /// blocked-app panel (design 05 and 10): 5, 10 and 20 minutes.
    public static let durations: [TimeInterval] = [5 * 60, 10 * 60, 20 * 60]

    var policyException: PolicyException {
        PolicyException(scope: scope, expiresAt: expiresAt)
    }
}

/// Why an exception request was refused.
public enum ExceptionError: Error, Equatable {
    /// Not one of `TimedException.durations`.
    case unsupportedDuration
    /// A strict session asks why the exception is needed.
    case reasonRequired
}

/// What happened when the owner asked for an exception.
public enum ExceptionOutcome: Equatable, Sendable {
    case granted(expiresAt: Date)
    /// A strict session: the owner must confirm first; nothing changed.
    case needsConfirmation
    /// Confirmed: ask again with the same request at or after this instant.
    case waitUntil(Date)
}

/// An exception request the owner confirmed in a strict session. The same
/// scope and duration continue it; anything else starts over.
struct ExceptionRequest: Equatable, Sendable {
    var scope: ExceptionScope
    var duration: TimeInterval
}

/// A strict-session exception waiting out its delay.
public struct PendingException: Equatable, Sendable {
    public var scope: ExceptionScope
    public var duration: TimeInterval
    /// When asking again grants it.
    public var availableAt: Date
}
