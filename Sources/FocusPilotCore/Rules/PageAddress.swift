import Foundation

/// One page for a timed exception (#14): its host without "www.", port,
/// path and query, minus parameters that only track the visit or position
/// a video (its start time, the playlist it came from), so the same lecture
/// stays the same page however it was reached. Mirrors `pageParts` in the
/// extension's policy.js; `Tests/ChromeExtension/fixtures/pages.json` pins both.
public enum PageAddress {
    static let tracking: Set<String> = ["fbclid", "gclid", "dclid", "msclkid", "igsh", "igshid", "si"]
    static let youTubeNoise: Set<String> = ["t", "pp", "feature", "ab_channel", "list", "index", "start_radio", "embeds_referring_euri"]

    /// "https://www.youtube.com/watch?v=1&t=42s" → "https://youtube.com/watch?v=1";
    /// nil for anything but an http(s) address.
    public static func canonical(_ url: String) -> String? {
        guard let page = Parts(url) else { return nil }
        let query = page.parameters.isEmpty ? "" : "?" + page.parameters.joined(separator: "&")
        return "https://\(page.host)\(page.port.map { ":\($0)" } ?? "")\(page.path)\(query)"
    }

    /// The host (without "www."), for checking a rule blocks it.
    public static func host(_ url: String) -> String? {
        Parts(url)?.host
    }

    /// Whether `url` is the excepted page: same host, port and path, and
    /// every parameter the exception names (others may be added).
    public static func matches(_ exceptionURL: String, _ url: String) -> Bool {
        guard let excepted = Parts(exceptionURL), let page = Parts(url),
              excepted.host == page.host, excepted.port == page.port, excepted.path == page.path else { return false }
        var left = page.parameters
        for parameter in excepted.parameters {
            guard let index = left.firstIndex(of: parameter) else { return false }
            left.remove(at: index)
        }
        return true
    }

    private struct Parts {
        var host: String
        var port: Int?
        var path: String
        /// Raw "key=value" pairs, sorted.
        var parameters: [String]

        init?(_ url: String) {
            guard !url.contains(" "), let components = URLComponents(string: url),
                  let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  var host = components.percentEncodedHost?.lowercased(), !host.isEmpty else { return nil }
            if host.hasSuffix(".") { host.removeLast() }
            if host.hasPrefix("www.") { host.removeFirst(4) }
            self.host = host
            let defaultPort = scheme == "https" ? 443 : 80
            port = components.port.flatMap { $0 == defaultPort ? nil : $0 }
            path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
            let youTube = SiteDomain.domain(host, isWithin: "youtube.com") || SiteDomain.domain(host, isWithin: "youtu.be")
            parameters = (components.percentEncodedQuery ?? "").split(separator: "&").map(String.init).filter { pair in
                let key = String(pair.prefix { $0 != "=" })
                return !key.hasPrefix("utm_") && !PageAddress.tracking.contains(key) && !(youTube && PageAddress.youTubeNoise.contains(key))
            }.sorted()
        }
    }
}
