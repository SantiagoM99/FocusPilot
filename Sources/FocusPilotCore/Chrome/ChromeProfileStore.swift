import Foundation

/// What the host knows about one Chrome profile's FocusPilot extension.
/// Chrome runs one extension instance and host per profile (decision 0003),
/// so each profile acknowledges policies separately.
public struct ChromeProfileRecord: Codable, Equatable, Sendable {
    public var profileID: String
    public var extensionVersion: String?
    public var incognitoAllowed = false
    /// False when the owner limited the extension's site access in Chrome;
    /// then only new page loads are blocked.
    public var allSitesAccess = true
    /// The last observation recorded, in the extension's sequence.
    public var lastSeq = 0
    /// Observations the sequence skipped; the extension keeps each one until
    /// acknowledged, so this stays 0 unless its storage was lost.
    public var missingObservations = 0
    public var appliedRevision: Int?
    public var appliedChecksum: String?
    public var appliedAt: Date?
    public var blockedPagesShown = 0
    public var lastSeenAt: Date
    /// The host process serving the profile now; nil once it stopped.
    public var hostProcessID: Int32?

    init(profileID: String, lastSeenAt: Date) {
        self.profileID = profileID
        self.lastSeenAt = lastSeenAt
    }
}

/// The host's records, one JSON file per profile, plus an observation log
/// the app does not need yet (kept small for diagnostics).
struct ChromeProfileStore {
    let location: StorageLocation
    static let logLimit = 256 * 1024

    /// Extension profile IDs are UUIDs; nothing else becomes a file name.
    static func isValid(_ profileID: String) -> Bool {
        UUID(uuidString: profileID) != nil
    }

    private var directory: URL { location.chromeProfilesDirectory }

    private func url(_ profileID: String, _ suffix: String) -> URL {
        directory.appending(path: profileID.uppercased() + suffix)
    }

    func record(_ profileID: String) throws -> ChromeProfileRecord? {
        guard Self.isValid(profileID), let data = try? Data(contentsOf: url(profileID, ".json")) else { return nil }
        return try ChromePolicyMailbox.decoder.decode(ChromeProfileRecord.self, from: data)
    }

    func records() throws -> [ChromeProfileRecord] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return try names.filter { $0.hasSuffix(".json") }.compactMap { try record(String($0.dropLast(5))) }
    }

    func save(_ record: ChromeProfileRecord) throws {
        try prepareDirectory()
        try PrivateFile.write(try CompiledPolicy.encoder().encode(record), to: url(record.profileID, ".json"))
    }

    func log(_ line: Data, for profileID: String) throws {
        try prepareDirectory()
        let log = url(profileID, ".log.jsonl")
        if let size = try? log.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > Self.logLimit {
            let previous = url(profileID, ".log.1.jsonl")
            try? FileManager.default.removeItem(at: previous)
            try FileManager.default.moveItem(at: log, to: previous)
        }
        if !FileManager.default.fileExists(atPath: log.path) {
            FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line + Data([0x0A]))
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }
}
