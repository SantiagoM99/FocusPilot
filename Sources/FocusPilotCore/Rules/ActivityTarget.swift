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

    /// Whether the two name the same app or tool, or overlapping sites
    /// (one domain within the other), so they cannot be both blocked and allowed.
    func overlaps(_ other: ActivityTarget) -> Bool {
        if case .site(let a) = self, case .site(let b) = other {
            return SiteDomain.domain(a, isWithin: b) || SiteDomain.domain(b, isWithin: a)
        }
        return key == other.key
    }

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
    /// has no usable domain. International names come out as punycode
    /// ("münchen.de" → "xn--mnchen-3ya.de"), the form DNR rules match.
    public static func normalized(_ typed: String) -> String? {
        guard var host = components(typed)?.encodedHost?.lowercased() else { return nil }
        if host.hasSuffix(".") { host.removeLast() }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy(isValidLabel) else { return nil }
        return host
    }

    /// Whether the typed text names a page or query, not just a site, so
    /// the editor can say the whole domain will be blocked.
    public static func namesAPage(_ typed: String) -> Bool {
        guard normalized(typed) != nil, let parts = components(typed) else { return false }
        return !["", "/"].contains(parts.percentEncodedPath) || parts.percentEncodedQuery != nil || parts.fragment != nil
    }

    /// Whether `domain` is `other` or one of its subdomains.
    static func domain(_ domain: String, isWithin other: String) -> Bool {
        domain == other || domain.hasSuffix("." + other)
    }

    private static func components(_ typed: String) -> URLComponents? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        return URLComponents(string: trimmed.contains("://") ? trimmed : "http://" + trimmed)
    }

    private static func isValidLabel(_ label: Substring) -> Bool {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        return (1...63).contains(label.count) && label.allSatisfy(allowed.contains)
            && label.first != "-" && label.last != "-"
    }
}
