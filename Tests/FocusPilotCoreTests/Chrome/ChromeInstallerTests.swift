import Foundation
import Testing
@testable import FocusPilotCore

@Suite("Installing the Chrome host and extension")
struct ChromeInstallerTests {
    private let root: URL
    private let installer: ChromeInstaller

    init() throws {
        root = try makeTemporaryDirectory()
        let bundled = root.appending(path: "FocusPilot.app/Contents/Resources/ChromeExtension")
        try FileManager.default.createDirectory(at: bundled.appending(path: "pages"), withIntermediateDirectories: true)
        try Data(#"{"version":"1.0.0"}"#.utf8).write(to: bundled.appending(path: "manifest.json"))
        try Data("page".utf8).write(to: bundled.appending(path: "pages/blocked.html"))
        installer = ChromeInstaller(manifestDirectory: root.appending(path: "NativeMessagingHosts"),
                                    hostExecutable: root.appending(path: "FocusPilot.app/Contents/Helpers/focuspilot-chrome-host"),
                                    bundledExtension: bundled,
                                    extensionDirectory: root.appending(path: "Data/Chrome Extension"))
    }

    private var manifestURL: URL {
        root.appending(path: "NativeMessagingHosts/\(ChromeExtension.hostName).json")
    }

    private func manifest() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
    }

    @Test func theManifestPointsChromeAtTheBundledHostForThisExtensionOnly() throws {
        #expect(try installer.installHost() == .installed)

        let manifest = try manifest()
        #expect(manifest["name"] as? String == ChromeExtension.hostName)
        #expect(manifest["type"] as? String == "stdio")
        #expect(manifest["path"] as? String == root.appending(path: "FocusPilot.app/Contents/Helpers/focuspilot-chrome-host").path)
        #expect(manifest["allowed_origins"] as? [String] == ["chrome-extension://\(ChromeExtension.id)/"])
    }

    @Test func installingAgainChangesNothing() throws {
        try installer.installHost()

        #expect(try installer.installHost() == .unchanged)
    }

    // Spike S2: a stale path fails with "Specified native messaging host not
    // found."; Chrome picks up a repaired manifest on the next connect.
    @Test func aManifestFromAMovedAppIsRepaired() throws {
        try installer.installHost()
        var stale = try manifest()
        stale["path"] = "/Old/FocusPilot.app/Contents/Helpers/focuspilot-chrome-host"
        try JSONSerialization.data(withJSONObject: stale).write(to: manifestURL)

        #expect(try installer.installHost() == .repaired(previousPath: "/Old/FocusPilot.app/Contents/Helpers/focuspilot-chrome-host"))
        #expect(try manifest()["path"] as? String == installer.hostExecutable.path)
    }

    @Test func anUnreadableManifestIsReplaced() throws {
        try FileManager.default.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: manifestURL)

        #expect(try installer.installHost() == .repaired(previousPath: nil))
    }

    @Test func theExtensionIsCopiedToItsStableFolder() throws {
        #expect(try installer.syncExtension())

        let copied = root.appending(path: "Data/Chrome Extension/pages/blocked.html")
        #expect(try String(contentsOf: copied, encoding: .utf8) == "page")
    }

    @Test func anUnchangedExtensionIsLeftAlone() throws {
        try installer.syncExtension()

        #expect(try !installer.syncExtension())
    }

    @Test func aNewBuildReplacesTheWholeFolder() throws {
        try installer.syncExtension()
        let stray = root.appending(path: "Data/Chrome Extension/old.js")
        try Data("old".utf8).write(to: stray)
        try Data("new page".utf8).write(to: installer.bundledExtension.appending(path: "pages/blocked.html"))

        #expect(try installer.syncExtension())
        #expect(try String(contentsOf: root.appending(path: "Data/Chrome Extension/pages/blocked.html"), encoding: .utf8) == "new page")
        #expect(!FileManager.default.fileExists(atPath: stray.path))
    }
}

@Suite("Trying FocusPilot with its own data folder")
struct ChromeTryOutTests {
    /// A try-out build with FOCUSPILOT_DATA_DIR must not repoint the owner's
    /// Chrome at itself; it registers its host for a Chrome started with
    /// `--user-data-dir` inside that folder instead.
    @Test func aDataFolderOverrideKeepsTheHostManifestInsideIt() {
        let directories = ChromeInstaller.chromeManifestDirectories(environment: ["FOCUSPILOT_DATA_DIR": "/tmp/fp-try"])
        #expect(directories.map(\.path) == ["/tmp/fp-try/Chrome User Data/NativeMessagingHosts"])
    }
}

/// Chrome Beta, Dev and Canary each read user-level host manifests from their
/// own data folder, so each installed channel gets the manifest.
@Suite("Chrome channels")
struct ChromeChannelTests {
    private let support: URL

    init() throws {
        support = try makeTemporaryDirectory()
    }

    private func install(_ channels: String...) throws {
        for channel in channels {
            try FileManager.default.createDirectory(at: support.appending(path: "Google/\(channel)"), withIntermediateDirectories: true)
        }
    }

    private func directories() -> [String] {
        ChromeInstaller.chromeManifestDirectories(applicationSupport: support, environment: [:])
            .map { String($0.path.dropFirst(support.path.count + 1)) }
    }

    @Test func everyInstalledChannelGetsItsOwnHostFolder() throws {
        try install("Chrome", "Chrome Beta", "Chrome Dev", "Chrome Canary")
        #expect(directories() == [
            "Google/Chrome/NativeMessagingHosts", "Google/Chrome Beta/NativeMessagingHosts",
            "Google/Chrome Dev/NativeMessagingHosts", "Google/Chrome Canary/NativeMessagingHosts",
        ])
    }

    @Test func channelsNeverRunHereAreLeftAlone() throws {
        try install("Chrome Canary")
        #expect(directories() == ["Google/Chrome Canary/NativeMessagingHosts"])
    }

    @Test func noChromeAtAllMeansNoFolder() {
        #expect(directories().isEmpty)
    }

    @Test func theManifestIsWrittenIntoEachChannelsFolder() throws {
        try install("Chrome", "Chrome Beta")
        let host = support.appending(path: "FocusPilot.app/Contents/Helpers/focuspilot-chrome-host")
        for directory in ChromeInstaller.chromeManifestDirectories(applicationSupport: support, environment: [:]) {
            let installer = ChromeInstaller(manifestDirectory: directory, hostExecutable: host,
                                            bundledExtension: support.appending(path: "none"), extensionDirectory: support.appending(path: "ext"))
            #expect(try installer.installHost() == .installed)
            let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appending(path: "\(ChromeExtension.hostName).json"))) as? [String: Any]
            #expect(manifest?["path"] as? String == host.path)
        }
    }
}
