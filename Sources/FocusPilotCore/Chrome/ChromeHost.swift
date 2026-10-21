import Foundation

/// The native messaging host's logic, run by `focuspilot-chrome-host` for one
/// Chrome profile. It reads the app's policy file, pushes it to the
/// extension, records the extension's observations and acknowledges each
/// one only once recorded. It never opens the databases (decision 0003).
///
/// Not thread-safe: the executable drives it from one serial queue.
public final class ChromeHost {
    public struct Environment: Sendable {
        public var isAppRunning: @Sendable () -> Bool
        public var openApp: @Sendable () -> Void
        public var now: @Sendable () -> Date
        public var processID: Int32
        public var send: @Sendable (Data) -> Void

        public init(isAppRunning: @escaping @Sendable () -> Bool, openApp: @escaping @Sendable () -> Void,
                    now: @escaping @Sendable () -> Date, processID: Int32, send: @escaping @Sendable (Data) -> Void) {
            self.isAppRunning = isAppRunning
            self.openApp = openApp
            self.now = now
            self.processID = processID
            self.send = send
        }
    }

    private let location: StorageLocation
    private let environment: Environment
    private let store: ChromeProfileStore
    private var sentRevision: Int?
    private var sentAppRunning: Bool?
    private var sentBuild: String??
    private var profileID: String?

    public init(location: StorageLocation, environment: Environment) {
        self.location = location
        self.environment = environment
        store = ChromeProfileStore(location: location)
    }

    /// Chrome passes the caller's origin as the first argument. The host
    /// manifest already limits it to the extension; this is defense in depth.
    public static func accepts(origin: String) -> Bool {
        origin == ChromeExtension.origin
    }

    public func receive(_ body: Data) {
        guard let message = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return }
        switch message["type"] as? String {
        case "hello": hello(message)
        case "observation": observation(message, body: body)
        case "open-app": environment.openApp()
        default: break
        }
    }

    /// Called every second: pushes a newer policy and app status changes.
    public func poll() {
        guard profileID != nil else { return }
        sendPolicy(force: false)
        sendStatus(force: false)
    }

    /// Chrome closed the port: this profile has no host until it reconnects.
    public func stop() {
        guard let profileID, var record = try? store.record(profileID),
              record.hostProcessID == environment.processID else { return }
        record.hostProcessID = nil
        try? store.save(record)
    }

    private func hello(_ message: [String: Any]) {
        guard let id = message["profileId"] as? String, ChromeProfileStore.isValid(id) else { return }
        profileID = id
        var record = existingRecord(id)
        record.extensionVersion = message["version"] as? String
        record.incognitoAllowed = message["incognitoAllowed"] as? Bool ?? false
        record.allSitesAccess = message["allSitesAccess"] as? Bool ?? false
        record.hostProcessID = environment.processID
        try? store.save(record)
        sendPolicy(force: true)
        sendStatus(force: true)
    }

    private func observation(_ message: [String: Any], body: Data) {
        guard let id = message["profileId"] as? String, ChromeProfileStore.isValid(id),
              let seq = message["seq"] as? Int, seq > 0 else { return }
        var record = existingRecord(id)
        // Observations can arrive out of order, so one below the last seen is
        // new when it filled a gap; anything else below is a resend.
        if seq > record.lastSeq || record.skippedSeqs.contains(seq) {
            do {
                try store.log(body, for: id)
            } catch {
                return // Not recorded, so not acknowledged: the extension resends it.
            }
            record.noteReceived(seq)
            apply(message, to: &record)
            guard (try? store.save(record)) != nil else { return }
        }
        send(["type": "ack", "seq": seq])
    }

    private func apply(_ message: [String: Any], to record: inout ChromeProfileRecord) {
        switch message["kind"] as? String {
        case "policy-applied":
            guard let revision = message["revision"] as? Int, revision >= record.appliedRevision ?? 0 else { return }
            record.appliedRevision = revision
            record.appliedChecksum = message["checksum"] as? String
            record.appliedAt = environment.now()
        case "blocked-shown":
            record.blockedPagesShown += 1
        default:
            break
        }
    }

    private func existingRecord(_ id: String) -> ChromeProfileRecord {
        var record = (try? store.record(id)) ?? ChromeProfileRecord(profileID: id.uppercased(), lastSeenAt: environment.now())
        record.lastSeenAt = environment.now()
        return record
    }

    private func sendPolicy(force: Bool) {
        guard let delivery = try? ChromePolicyMailbox.read(location),
              force || delivery.policy.revision != sentRevision,
              let encoded = try? CompiledPolicy.encoder().encode(delivery),
              var object = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        else { return }
        object["type"] = "policy"
        sentRevision = delivery.policy.revision
        send(object)
    }

    /// Sent when the app starts or stops, and when an app update lands a new
    /// extension build, which can happen after hello.
    private func sendStatus(force: Bool) {
        let running = environment.isAppRunning()
        let build = extensionBuildOnDisk()
        guard force || running != sentAppRunning || sentBuild != .some(build) else { return }
        sentAppRunning = running
        sentBuild = .some(build)
        var status: [String: Any] = ["type": "status", "appRunning": running]
        status["extensionBuild"] = build
        send(status)
    }

    /// The `version_name` build-app.sh stamps into the extension folder's
    /// manifest; the extension reloads itself when it runs another build.
    private func extensionBuildOnDisk() -> String? {
        let manifest = location.chromeExtensionDirectory.appending(path: "manifest.json")
        guard let data = try? Data(contentsOf: manifest),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["version_name"] as? String
    }

    private func send(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
        environment.send(data)
    }
}
