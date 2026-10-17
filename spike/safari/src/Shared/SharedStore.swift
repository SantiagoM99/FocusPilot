// Throwaway spike for issue #1. Compiled into the app, the extension handler and the probe tool
// (scripts/generate.sh concatenates it into each target's single source file).
import Foundation
import Security

enum Spike {
    static let groupID = "group.com.focuspilot.spike.s1"
    static let extensionBundleID = "com.focuspilot.spike.s1.Extension"
    // Must match the home-relative temporary exception in Extension.entitlements.
    static let fallbackRelativePath = "Library/Application Support/FocusPilotSpikeS1"
    static let policyFile = "policy.json"
    static let inboxFile = "inbox.jsonl"
    static let appEventsFile = "app-events.jsonl"
    static let commandFile = "command.json"
}

struct StoreLocation {
    let transport: String
    let url: URL
}

struct StoreProbe {
    let transport: String
    let path: String
    let writable: Bool
    let policyPresent: Bool
    let error: String?

    var dictionary: [String: Any] {
        var d: [String: Any] = ["transport": transport, "path": path, "writable": writable, "policyPresent": policyPresent]
        if let error { d["error"] = error }
        return d
    }
}

enum SharedStore {
    // Inside the sandbox NSHomeDirectory() is the container, so ask the user database for the real one.
    static func realHome() -> URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    // True only when this binary was signed with the App Group claim (build.sh --app-group).
    static func claimsAppGroup() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil)
        else { return false }
        return (value as? [String])?.contains(Spike.groupID) ?? false
    }

    // Home-relative temporary exception by default. The "group." App Group is only tried when the
    // binary claims it: without a team-ID prefix or provisioning profile, every touch of that
    // container is a "would like to access data from other apps" prompt whose Allow does not stick
    // (SPIKE_NOTES.md, Permission prompts). On macOS containerURL returns a path even for an
    // unauthorised group ID, so only a real write proves access.
    static func candidates() -> [StoreLocation] {
        var out: [StoreLocation] = []
        if claimsAppGroup(), let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Spike.groupID) {
            out.append(StoreLocation(transport: "app-group", url: group.appendingPathComponent("FocusPilotSpikeS1", isDirectory: true)))
        }
        out.append(StoreLocation(transport: "home-exception", url: realHome().appendingPathComponent(Spike.fallbackRelativePath, isDirectory: true)))
        return out
    }

    static func probe(_ location: StoreLocation) -> StoreProbe {
        let fm = FileManager.default
        let marker = location.url.appendingPathComponent(".probe-\(getpid())")
        do {
            try fm.createDirectory(at: location.url, withIntermediateDirectories: true)
            try Data("probe".utf8).write(to: marker)
            try fm.removeItem(at: marker)
            let policyPresent = fm.isReadableFile(atPath: location.url.appendingPathComponent(Spike.policyFile).path)
            return StoreProbe(transport: location.transport, path: location.url.path, writable: true, policyPresent: policyPresent, error: nil)
        } catch {
            return StoreProbe(transport: location.transport, path: location.url.path, writable: false, policyPresent: false, error: "\(error)")
        }
    }

    static func probeAll() -> [(StoreLocation, StoreProbe)] {
        candidates().map { ($0, probe($0)) }
    }

    static func readJSON(_ url: URL) -> Any? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    static func writeAtomically(_ object: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    // Several handler processes may append at once; an exclusive flock around one write keeps
    // every JSON line whole.
    static func appendLines(_ objects: [[String: Any]], to url: URL) throws {
        var blob = Data()
        for object in objects {
            blob.append(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            blob.append(0x0A)
        }
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN) }
        let written = blob.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard written == blob.count else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    static func now() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }
}
