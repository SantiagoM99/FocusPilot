import Darwin
import Foundation
import Security
import Testing
@testable import FocusPilotCore

/// Who may ask for a site exception over the command socket (#14): the Chrome
/// host bundled with this app, verified by its code signature through the
/// connection's audit token, and only while a Google-signed Chrome runs it.
@Suite("Exception callers")
final class ExceptionCallerTests {
    private static let chrome = URL(fileURLWithPath: "/Applications/Google Chrome.app")
    private let directory: URL

    init() throws { directory = try makeShortDirectory() }
    deinit { try? FileManager.default.removeItem(at: directory) }

    private func staticallySatisfies(_ url: URL, _ requirement: SecRequirement) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return false }
        return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: chrome.path)))
    func googlesChromeMeetsTheChromeRequirement() throws {
        #expect(staticallySatisfies(Self.chrome, try #require(ExceptionCallerCheck.chromeRequirement())))
    }

    /// The path pattern alone was not enough: any binary can sit at a path
    /// that looks like Chrome's.
    @Test func aBinaryOnlyNamedLikeChromeDoesNot() throws {
        let fake = directory.appending(path: "Google Chrome.app/Contents/MacOS")
        try FileManager.default.createDirectory(at: fake, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/ls"), to: fake.appending(path: "Google Chrome"))
        #expect(!staticallySatisfies(fake.appending(path: "Google Chrome"), try #require(ExceptionCallerCheck.chromeRequirement())))
        #expect(!staticallySatisfies(URL(fileURLWithPath: "/bin/zsh"), try #require(ExceptionCallerCheck.chromeRequirement())),
                "Apple-signed is not Google-signed")
    }

    @Test func theConnectionsAuditTokenNamesTheProcessAtTheOtherEnd() throws {
        let path = directory.appending(path: "cli.sock").path
        let seen = Locked<CommandPeer?>(nil)
        let server = CommandSocketServer(path: path) { (_: CommandRequest, peer: CommandPeer) in
            seen.withLock { $0 = peer }
            return .refused("ok")
        }
        try server.start()
        defer { server.stop() }
        _ = try CommandSocketClient(path: path).send(.tasks(nil))

        let peer = try #require(seen.withLock { $0 })
        let token = try #require(peer.auditToken)
        #expect(CommandPeer.processID(of: token) == getpid())
        let code = try #require(ExceptionCallerCheck.code(for: token))
        var staticCode: SecStaticCode?
        #expect(SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess)
        var url: CFURL?
        #expect(SecCodeCopyPath(try #require(staticCode), [], &url) == errSecSuccess)
        #expect((url as URL?)?.resolvingSymlinksInPath().path == CommandPeer.executablePath(of: getpid()).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path })
    }

    /// The test process connects as if it were the host: right code, but no
    /// Chrome started it, so it is refused; and a host other than the bundled one is refused too.
    @Test func aCallerNotStartedByChromeOrNotTheBundledHostIsRefused() throws {
        let path = directory.appending(path: "cli.sock").path
        let seen = Locked<CommandPeer?>(nil)
        let server = CommandSocketServer(path: path) { (_: CommandRequest, peer: CommandPeer) in
            seen.withLock { $0 = peer }
            return .refused("ok")
        }
        try server.start()
        defer { server.stop() }
        _ = try CommandSocketClient(path: path).send(.tasks(nil))
        let peer = try #require(seen.withLock { $0 })
        let me = URL(fileURLWithPath: try #require(CommandPeer.executablePath(of: getpid())))

        #expect(!ExceptionCallerCheck.chromeHost(at: me).allows(peer))
        #expect(!ExceptionCallerCheck.chromeHost(at: URL(fileURLWithPath: "/bin/ls")).allows(peer))
        #expect(!ExceptionCallerCheck.chromeHost(at: me).allows(nil))
    }
}
