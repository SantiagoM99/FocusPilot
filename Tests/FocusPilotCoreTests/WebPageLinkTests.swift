import Foundation
import Testing
@testable import FocusPilotCore

@Suite("Web page links")
struct WebPageLinkTests {
    @Test(arguments: [
        ("overleaf.com/project/nlp-report", "https://overleaf.com/project/nlp-report", "overleaf.com"),
        ("https://www.overleaf.com/project/1", "https://www.overleaf.com/project/1", "overleaf.com"),
        ("  http://docs.google.com/d/1?x=2  ", "http://docs.google.com/d/1?x=2", "docs.google.com"),
        ("arxiv.org", "https://arxiv.org", "arxiv.org"),
    ])
    func typedAddressesBecomeAbsoluteURLs(typed: String, url: String, domain: String) throws {
        let page = try WebPageLink(typed)

        #expect(page.url == url)
        #expect(page.domain == domain)
    }

    @Test(arguments: ["", "overleaf", "not a url", "ftp://example.com/file", "file:///Users/owner", "javascript:alert(1)"])
    func otherTextIsRefused(_ typed: String) {
        #expect(throws: WebPageLinkError.invalid) { try WebPageLink(typed) }
    }

    @Test func theInvalidMessageSaysWhatToType() {
        #expect(WebPageLinkError.invalid.message == "Not a valid URL. Include a domain, e.g. overleaf.com/project/nlp-report")
    }

    @Test func aLinkShowsItsHostPathAndQuery() throws {
        #expect(try WebPageLink("https://www.overleaf.com/project/nlp-report").displayName == "overleaf.com/project/nlp-report")
        #expect(try WebPageLink("youtube.com/watch?v=lecture-7#t=30").displayName == "youtube.com/watch?v=lecture-7")
        #expect(try WebPageLink("arxiv.org/").displayName == "arxiv.org")
    }
}
