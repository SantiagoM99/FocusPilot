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

    /// `~/Library/Application Support/FocusPilot`.
    public static func applicationSupport() -> StorageLocation {
        StorageLocation(directory: URL.applicationSupportDirectory.appending(path: "FocusPilot", directoryHint: .isDirectory))
    }
}
