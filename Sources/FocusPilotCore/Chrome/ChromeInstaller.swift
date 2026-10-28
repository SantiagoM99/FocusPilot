import CryptoKit
import Foundation

/// Sets up Chrome enforcement for the current user at every launch: the
/// native host manifest (user level only) pointing at the host inside this
/// app bundle, and the unpacked extension in its stable folder.
public struct ChromeInstaller: Sendable {
    public enum HostInstall: Equatable, Sendable {
        case installed
        /// The manifest named another path (the app moved) or was unreadable.
        case repaired(previousPath: String?)
        case unchanged
    }

    public let manifestDirectory: URL
    public let hostExecutable: URL
    public let bundledExtension: URL
    public let extensionDirectory: URL

    public init(manifestDirectory: URL, hostExecutable: URL, bundledExtension: URL, extensionDirectory: URL) {
        self.manifestDirectory = manifestDirectory
        self.hostExecutable = hostExecutable
        self.bundledExtension = bundledExtension
        self.extensionDirectory = extensionDirectory
    }

    /// Chrome's per-user host folder, or nil when Chrome was never run here.
    /// With `FOCUSPILOT_DATA_DIR` (trying a build without touching the
    /// owner's setup) it is the host folder of a Chrome started with
    /// `--user-data-dir="$FOCUSPILOT_DATA_DIR/Chrome User Data"`, so the
    /// owner's Chrome keeps the host of the FocusPilot they use.
    public static func chromeManifestDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        if let override = environment["FOCUSPILOT_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
                .appending(path: "Chrome User Data/NativeMessagingHosts", directoryHint: .isDirectory)
        }
        let chrome = URL.applicationSupportDirectory.appending(path: "Google/Chrome", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: chrome.path) else { return nil }
        return chrome.appending(path: "NativeMessagingHosts", directoryHint: .isDirectory)
    }

    private var manifestURL: URL {
        manifestDirectory.appending(path: "\(ChromeExtension.hostName).json")
    }

    private var manifest: [String: Any] {
        [
            "name": ChromeExtension.hostName,
            "description": "FocusPilot",
            "path": hostExecutable.path,
            "type": "stdio",
            "allowed_origins": [ChromeExtension.origin],
        ]
    }

    @discardableResult
    public func installHost() throws -> HostInstall {
        let wanted = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
        let result: HostInstall
        if let existing = try? Data(contentsOf: manifestURL) {
            let installed = try? JSONSerialization.jsonObject(with: existing) as? [String: Any]
            if let installed, NSDictionary(dictionary: installed).isEqual(to: manifest) { return .unchanged }
            result = .repaired(previousPath: installed?["path"] as? String)
        } else {
            result = .installed
        }
        try FileManager.default.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)
        try wanted.write(to: manifestURL, options: .atomic)
        return result
    }

    /// Copies the bundled extension when its files differ from the
    /// installed ones. The folder is swapped in one step, so Chrome never
    /// reads a half-copied extension. Returns whether anything changed.
    @discardableResult
    public func syncExtension() throws -> Bool {
        let fileManager = FileManager.default
        guard try Self.digest(of: bundledExtension) != (try? Self.digest(of: extensionDirectory)) else { return false }
        let parent = extensionDirectory.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staged = parent.appending(path: ".\(extensionDirectory.lastPathComponent)-\(UUID().uuidString)")
        try fileManager.copyItem(at: bundledExtension, to: staged)
        if fileManager.fileExists(atPath: extensionDirectory.path) {
            _ = try fileManager.replaceItemAt(extensionDirectory, withItemAt: staged)
        } else {
            try fileManager.moveItem(at: staged, to: extensionDirectory)
        }
        return true
    }

    /// Relative paths and contents of every file under `folder`.
    static func digest(of folder: URL) throws -> String {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: folder.path) else { throw CocoaError(.fileNoSuchFile) }
        var hash = SHA256()
        let paths = (fileManager.subpaths(atPath: folder.path) ?? []).sorted()
        for path in paths {
            var isDirectory: ObjCBool = false
            let url = folder.appending(path: path)
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
            hash.update(data: Data(path.utf8))
            hash.update(data: try Data(contentsOf: url))
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
