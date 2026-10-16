import Foundation

/// Something the owner blocks or allows: a site, a Mac app, or a
/// command-line tool such as Herdr that runs inside a terminal.
///
/// Sites are whole domains, subdomains included, because that is what the
/// extensions block (`||instagram.com/`, spike S1). Narrower access to one
/// page belongs to timed exceptions scoped to an exact URL (#14).
public enum ActivityTarget: Hashable, Codable, Sendable {
    case site(domain: String)
    case app(bundleID: String, name: String)
    case tool(command: String)

    /// Equal for the same site, app bundle or command, whatever the app's
    /// display name.
    var key: String {
        switch self {
        case .site(let domain): "site:\(domain)"
        case .app(let bundleID, _): "app:\(bundleID.lowercased())"
        case .tool(let command): "tool:\(command)"
        }
    }

    /// "instagram.com", "Instagram", "herdr".
    public var displayName: String {
        switch self {
        case .site(let domain): domain
        case .app(_, let name): name
        case .tool(let command): command
        }
    }
}

/// Turns what the owner typed into the domain the extensions block.
public enum SiteDomain {
    /// "https://www.YouTube.com/watch?v=1" → "youtube.com"; nil if the text
    /// has no usable domain. Only ASCII names are accepted.
    public static func normalized(_ typed: String) -> String? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "http://" + trimmed
        guard var host = URLComponents(string: withScheme)?.host else { return nil }
        if host.hasSuffix(".") { host.removeLast() }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy(isValidLabel) else { return nil }
        return host
    }

    private static func isValidLabel(_ label: Substring) -> Bool {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        return (1...63).contains(label.count) && label.allSatisfy(allowed.contains)
            && label.first != "-" && label.last != "-"
    }
}
