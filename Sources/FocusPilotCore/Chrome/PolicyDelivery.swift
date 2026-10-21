import Foundation

/// What the blocked page shows about the session: the task and its next
/// step. Not part of the rules, so it does not change the checksum.
public struct FocusContext: Hashable, Codable, Sendable {
    public var title: String
    public var nextAction: String?
    public var projectTitle: String?

    public init(title: String, nextAction: String? = nil, projectTitle: String? = nil) {
        self.title = title
        self.nextAction = nextAction
        self.projectTitle = projectTitle
    }
}

/// One publish from FocusCoordinator, the single source of policies.
public struct PolicyDelivery: Hashable, Codable, Sendable {
    public var policy: CompiledPolicy
    /// Present while session rules apply.
    public var focus: FocusContext?
    /// Names the data folder that issued the revision, set by the mailbox.
    /// Revisions restart when the owner resets FocusPilot's data, so the
    /// extension takes a delivery from another source whatever its revision.
    public var source: String?

    public init(policy: CompiledPolicy, focus: FocusContext?, source: String? = nil) {
        self.policy = policy
        self.focus = focus
        self.source = source
    }
}

/// Hands each policy to the Chrome host through a file only the owner can
/// read (decision 0003: the app publishes a snapshot; helpers read it).
/// The host may run while the app is quit, so the file keeps the last policy.
public actor ChromePolicyMailbox: PolicyPublisher {
    private let location: StorageLocation

    public init(location: StorageLocation) {
        self.location = location
    }

    public func publish(_ delivery: PolicyDelivery) async {
        do {
            // The coordinator can publish an interleaved older revision;
            // the file only moves forward.
            if let current = try? Self.read(location), current.policy.revision > delivery.policy.revision { return }
            try FileManager.default.createDirectory(at: location.chromeDirectory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            var stamped = delivery
            stamped.source = try source()
            try PrivateFile.write(try CompiledPolicy.encoder().encode(stamped), to: location.chromePolicyURL)
        } catch {
            // Nothing to tell the owner here: the host keeps the last policy
            // and protection status reports the missing acknowledgement.
        }
    }

    /// Made once per data folder, so a reset folder gets a new one.
    private func source() throws -> String {
        let url = location.chromeDirectory.appending(path: "source")
        if let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8),
           UUID(uuidString: text) != nil { return text }
        let made = UUID().uuidString
        try PrivateFile.write(Data(made.utf8), to: url)
        return made
    }

    public static func read(_ location: StorageLocation) throws -> PolicyDelivery? {
        guard let data = try? Data(contentsOf: location.chromePolicyURL) else { return nil }
        return try decoder.decode(PolicyDelivery.self, from: data)
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Atomic writes readable only by the owner.
enum PrivateFile {
    static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
