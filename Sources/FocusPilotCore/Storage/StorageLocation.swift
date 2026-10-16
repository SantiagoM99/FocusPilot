import Foundation

/// Where FocusPilot keeps its two SQLite files.
///
/// Owner data and cache data are separate files, so clearing or losing the
/// cache cannot touch tasks, preferences, deadlines or focus rules.
public struct StorageLocation: Sendable {
    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Authoritative records: everything the owner entered or decided.
    public var ownerDatabaseURL: URL {
        directory.appending(path: "FocusPilot.sqlite")
    }

    /// Derived values that can be rebuilt; safe to delete at any time.
    public var cacheDatabaseURL: URL {
        directory.appending(path: "Cache.sqlite")
    }

    /// The cache database together with its WAL-mode companions. Deleting
    /// only the main file and leaving a stale `-wal`/`-shm` behind can make
    /// the next open fail, so the cache is always removed as a set.
    var cacheDatabaseFiles: [URL] {
        ["", "-wal", "-shm"].map { suffix in
            directory.appending(path: "Cache.sqlite\(suffix)")
        }
    }

    /// `~/Library/Application Support/FocusPilot`, or `FOCUSPILOT_DATA_DIR`
    /// when set, so the app and CLI can be tried without touching the
    /// owner's data.
    public static func applicationSupport(environment: [String: String] = ProcessInfo.processInfo.environment)
        -> StorageLocation {
        if let override = environment["FOCUSPILOT_DATA_DIR"], !override.isEmpty {
            return StorageLocation(directory: URL(fileURLWithPath: override, isDirectory: true))
        }
        return StorageLocation(directory: URL.applicationSupportDirectory.appending(path: "FocusPilot", directoryHint: .isDirectory))
    }

    /// The focuspilot CLI's socket and inbox, in a folder only the owner can open.
    var commandLineDirectory: URL {
        directory.appending(path: "CommandLine", directoryHint: .isDirectory)
    }

    public var commandSocketPath: String {
        commandLineDirectory.appending(path: "cli.sock").path
    }

    public var inbox: TaskInbox {
        TaskInbox(directory: commandLineDirectory)
    }
}
