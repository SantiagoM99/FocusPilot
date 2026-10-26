import Foundation

/// A browser the owner brought to the front, by bundle ID.
public enum FrontBrowser: Equatable, Sendable {
    case chrome
    /// Covered by the owner's own blocker (decision 0003, 2026-10-20).
    case safari
    /// No FocusPilot extension: nothing blocks sites there.
    case unsupported(name: String)

    /// Other browsers, including Chrome's other channels: the extension and
    /// its native host are set up for stable Chrome only.
    private static let unsupported: Set<String> = [
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
        "company.thebrowser.Browser", "company.thebrowser.dia", "com.brave.Browser", "com.microsoft.edgemac",
        "com.operasoftware.Opera", "com.operasoftware.OperaGX", "com.vivaldi.Vivaldi", "com.kagi.kagimacOS",
        "app.zen-browser.zen", "com.duckduckgo.macos.browser", "org.torproject.torbrowser", "org.chromium.Chromium",
        "com.google.Chrome.canary", "com.google.Chrome.beta", "com.google.Chrome.dev",
        "com.apple.SafariTechnologyPreview", "ru.yandex.desktop.yandex-browser", "org.waterfoxproject.waterfox",
    ]

    /// Nil for an app that isn't a browser.
    public init?(_ bundleID: String, name: String) {
        switch bundleID {
        case "com.google.Chrome": self = .chrome
        case "com.apple.Safari": self = .safari
        case let id where Self.unsupported.contains(id): self = .unsupported(name: name)
        default: return nil
        }
    }
}

/// The Browsers fact of protection status (design 01, 03, 04 and 11). Apps
/// are a separate fact (`AppProtectionText`); the two are never summarized
/// as one "protected". It claims protection only on evidence: every
/// connected Chrome profile acknowledged the current policy with full site
/// access and Incognito allowed, since FocusPilot started or the Mac woke.
public struct BrowserProtection: Equatable, Sendable {
    public enum Level: Equatable, Sendable {
        case protected, syncing, degraded, unknown
    }

    public var level: Level
    /// "Chrome protected · Incognito unprotected".
    public var line: String
    /// The sidebar footer: "Chrome · Protected". It names Chrome, not
    /// "Browsers", since Safari is never verified.
    public var footer: String
    public var detail: String?
    /// FocusPilot can't see Safari's blocker, so this line never changes.
    public let safari = "Safari · external blocker, not verified"

    /// `confirmedSinceStart` comes from `ProtectionEvidence`; `front` is the
    /// browser the owner last had in front, if any.
    public init(profiles: [ChromeProfileStatus], chromeRunning: Bool, confirmedSinceStart: Bool,
                inSession: Bool, front: FrontBrowser?) {
        let connected = profiles.filter { !$0.isDisconnected }
        let disconnected = profiles.count - connected.count
        let pending = connected.contains { !$0.hasAcknowledged }

        if inSession, case .unsupported(let name) = front {
            self.init(.degraded, "\(name) in front · not protected", "\(name) · not protected",
                      "Chrome rules still apply; \(name) has no FocusPilot extension")
        } else if profiles.isEmpty {
            self.init(.degraded, "Chrome extension not connected", "Chrome · Not connected",
                      "Load the FocusPilot extension in Chrome: Settings › Blocking › Chrome")
        } else if !chromeRunning {
            self.init(.unknown, "Chrome not running", "Chrome · Unknown", "It gets the current policy when it opens")
        } else if connected.isEmpty {
            // Before the confirmation check: a turned-off extension never confirms.
            self.init(.degraded, "Chrome extension not connected", "Chrome · Disconnected",
                      "Chrome is open but the extension isn't connected. Check that it's on in chrome://extensions.")
        } else if !confirmedSinceStart {
            self.init(.unknown, "Chrome not confirmed yet", "Chrome · Unknown",
                      "Waiting for Chrome to acknowledge the policy since FocusPilot started or the Mac woke")
        } else if connected.contains(where: { !$0.allSitesAccess }) {
            self.init(.degraded, "Chrome extension needs site access", "Chrome · Permission missing",
                      "Chrome sites are not blocked until you allow the extension on all sites in chrome://extensions")
        } else if pending && inSession && front == .chrome {
            self.init(.degraded, "Chrome in front · not yet protected", "Chrome · Not yet protected",
                      "A Chrome profile hasn't applied the current policy yet")
        } else if pending {
            self.init(.syncing, "Chrome syncing", "Chrome · Syncing", "A Chrome profile hasn't applied the current policy yet")
        } else if disconnected > 0 {
            self.init(.degraded, "Chrome protected · \(disconnected) profile\(disconnected == 1 ? "" : "s") disconnected",
                      "Chrome · Disconnected",
                      "A profile's extension isn't connected. Forget it in Settings if you no longer use it.")
        } else if connected.contains(where: { !$0.incognitoAllowed }) {
            self.init(.degraded, "Chrome protected · Incognito unprotected", "Chrome · Incognito unprotected",
                      "Turn on Allow in Incognito for the FocusPilot extension in chrome://extensions")
        } else {
            self.init(.protected, "Chrome protected", "Chrome · Protected", Self.acknowledged(connected))
        }
    }

    private init(_ level: Level, _ line: String, _ footer: String, _ detail: String?) {
        self.level = level
        self.line = line
        self.footer = footer
        self.detail = detail
    }

    private static func acknowledged(_ profiles: [ChromeProfileStatus]) -> String {
        let revision = profiles.compactMap(\.acknowledgedRevision).min() ?? 0
        let who = profiles.count == 1 ? "Chrome" : "\(profiles.count) Chrome profiles"
        return "\(who) acknowledged policy rev. \(revision)"
    }
}

/// Whether Chrome confirmed the policy since FocusPilot started or the Mac
/// woke (#17): until every connected profile acknowledges a revision newer
/// than the one current at that moment, status is unknown. Both launch and
/// wake publish a new revision, so this always settles once Chrome answers.
public struct ProtectionEvidence: Equatable, Sendable {
    private var floor: Int?
    public private(set) var isConfirmed = false

    /// `currentRevision`: the policy Chrome had before the launch or wake.
    public init(currentRevision: Int? = nil) {
        floor = currentRevision
    }

    public mutating func markStale(currentRevision: Int?) {
        self = ProtectionEvidence(currentRevision: currentRevision)
    }

    public mutating func update(_ profiles: [ChromeProfileStatus]) {
        guard !isConfirmed else { return }
        let connected = profiles.filter { !$0.isDisconnected }
        isConfirmed = !connected.isEmpty && connected.allSatisfy {
            guard let revision = $0.acknowledgedRevision else { return false }
            return floor.map { revision > $0 } ?? true
        }
    }
}

extension ChromeProfileStatus {
    var isDisconnected: Bool {
        if case .disconnected = state { true } else { false }
    }

    var acknowledgedRevision: Int? {
        if case .acknowledged(let revision) = state { revision } else { nil }
    }

    var hasAcknowledged: Bool { acknowledgedRevision != nil }
}
