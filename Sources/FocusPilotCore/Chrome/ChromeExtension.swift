import Foundation

/// The FocusPilot Chrome extension and its native host.
public enum ChromeExtension {
    /// Fixed by the public key in the extension's manifest, so the host
    /// manifest can name it before the owner loads the extension.
    public static let id = "chmamkccdgghcchjaedemhkkiebdfabd"
    public static var origin: String { "chrome-extension://\(id)/" }
    public static let hostName = "com.santiagom99.focuspilot"
    /// Stable Chrome, the only channel the host manifest is installed for.
    public static let chromeBundleID = "com.google.Chrome"
}

extension StorageLocation {
    /// What the app and the Chrome host share; only the owner can open it.
    public var chromeDirectory: URL {
        directory.appending(path: "Chrome", directoryHint: .isDirectory)
    }

    /// The latest policy, written by the app and read by the host.
    public var chromePolicyURL: URL {
        chromeDirectory.appending(path: "policy.json")
    }

    /// One record and observation log per Chrome profile, written by the host.
    var chromeProfilesDirectory: URL {
        chromeDirectory.appending(path: "Profiles", directoryHint: .isDirectory)
    }

    /// The unpacked extension the owner loads once in chrome://extensions.
    /// It stays here across app updates; the app refreshes its files.
    public var chromeExtensionDirectory: URL {
        directory.appending(path: "Chrome Extension", directoryHint: .isDirectory)
    }
}
