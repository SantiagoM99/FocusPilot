import Foundation

/// A web page linked to a task or project, as the absolute http(s) URL the
/// browser opens. A typed address without a scheme gets https.
public struct WebPageLink: Codable, Equatable, Sendable {
    public var url: String

    public init(_ typed: String) throws {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let absolute = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let parts = URLComponents(string: absolute), ["http", "https"].contains(parts.scheme?.lowercased()),
              SiteDomain.normalized(absolute) != nil else { throw WebPageLinkError.invalid }
        url = absolute
    }

    /// The site, as block rules and the allowed list name it.
    public var domain: String { SiteDomain.normalized(url) ?? url }

    /// "Overleaf" for overleaf.com: links have no title of their own.
    public var siteName: String {
        (domain.split(separator: ".").first.map(String.init) ?? domain).capitalized
    }

    /// "overleaf.com/project/nlp-report", "youtube.com/watch?v=1": host,
    /// path and query, without the scheme, "www." or a fragment.
    public var displayName: String {
        let parts = URLComponents(string: url)
        let path = parts?.path ?? ""
        return domain + (path == "/" ? "" : path) + (parts?.query.map { "?" + $0 } ?? "")
    }
}

public enum WebPageLinkError: Error, Equatable {
    case invalid

    public var message: String {
        "Not a valid URL"
    }
}
