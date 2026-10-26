import Foundation

/// Chrome's front tab, as one profile reported it while observing (#21):
/// its domain, or nil when no web page of that profile is in front.
public struct ChromeTabReport: Equatable, Sendable, Codable {
    public var domain: String?
    public var at: Date
}

/// Front-tab reports on their way from the Chrome hosts to the app: one
/// JSON line each, appended by the hosts and drained by the app every few
/// seconds into raw activity. Only a domain is ever written, and only while
/// observing with the app running, so nothing waits here long.
public struct ChromeActivityInbox: Sendable {
    let location: StorageLocation

    public init(location: StorageLocation) {
        self.location = location
    }

    private var url: URL { location.chromeDirectory.appending(path: "activity.jsonl") }

    /// Keeps only the domain `reported` names, if any.
    func append(reported: String?, at: Date) throws {
        let report = ChromeTabReport(domain: reported.flatMap(SiteDomain.normalized), at: at)
        try FileManager.default.createDirectory(at: location.chromeDirectory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: try CompiledPolicy.encoder().encode(report) + Data([0x0A]))
    }

    /// Every report, oldest first, and empties the inbox. Reports older than
    /// the raw activity retention are dropped.
    public func drain(now: Date) -> [ChromeTabReport] {
        let taken = url.deletingLastPathComponent().appending(path: "activity.draining.jsonl")
        guard (try? FileManager.default.moveItem(at: url, to: taken)) != nil else { return [] }
        defer { try? FileManager.default.removeItem(at: taken) }
        let text = (try? String(contentsOf: taken, encoding: .utf8)) ?? ""
        let cutoff = now.addingTimeInterval(-TaskRepository.rawActivityRetention)
        return text.split(separator: "\n")
            .compactMap { try? ChromePolicyMailbox.decoder.decode(ChromeTabReport.self, from: Data($0.utf8)) }
            .filter { $0.at >= cutoff }
            .sorted { $0.at < $1.at }
    }
}
