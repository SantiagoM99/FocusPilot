import Foundation

/// A session policy as the extensions receive it. FocusCoordinator wraps every
/// publish with a schema version, a revision that only grows (stored in the
/// owner database, so it keeps growing across relaunches) and the instant it
/// takes effect, so an extension can reject a stale or out-of-order policy
/// (decision 0003, 2026-10-14; required by #15).
public struct PublishedPolicy: Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion = Self.currentSchemaVersion
    public var revision: Int
    public var effectiveAt: Date
    /// `nil` means no session rules apply.
    public var session: SessionPolicy?

    public init(revision: Int, effectiveAt: Date, session: SessionPolicy?) {
        self.revision = revision
        self.effectiveAt = effectiveAt
        self.session = session
    }
}

/// Delivers policies to the browser extensions. Delivery itself arrives with
/// the extensions (#13, #16); until then the app uses `PolicyNotDelivered`.
public protocol PolicyPublisher: Sendable {
    func publish(_ policy: PublishedPolicy) async
}

/// Tells the owner about a session event, such as reaching the planned end.
public protocol FocusNoticeSink: Sendable {
    func deliver(_ notice: FocusNotice) async
}

/// Keeps nothing: no extension is installed to receive policies yet.
public struct PolicyNotDelivered: PolicyPublisher {
    public init() {}
    public func publish(_ policy: PublishedPolicy) async {}
}

/// Drops notices; the app supplies a sink that shows them.
public struct NoticesIgnored: FocusNoticeSink {
    public init() {}
    public func deliver(_ notice: FocusNotice) async {}
}
