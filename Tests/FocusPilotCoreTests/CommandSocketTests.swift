import Foundation
import Testing
@testable import FocusPilotCore

/// A fresh short directory: socket paths must fit in 104 bytes, which the
/// usual temporary directory does not leave room for.
func makeShortDirectory() throws -> URL {
    let url = URL(fileURLWithPath: "/tmp/fp-\(UUID().uuidString.prefix(8))", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("Command socket")
final class CommandSocketTests {
    private let directory: URL
    private var path: String { directory.appending(path: "cli.sock").path }
    private let scope = HerdrTaskScope(now: nil, projectTitle: "NLP report", tasks: [])

    init() throws {
        directory = try makeShortDirectory()
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func server(answer: CommandResponse? = nil) -> CommandSocketServer {
        let answer = answer ?? .tasks(scope)
        return CommandSocketServer(path: path) { _ in answer }
    }

    @Test func aRequestGetsTheHandlersAnswer() async throws {
        let server = server()
        try server.start()
        defer { server.stop() }

        #expect(try CommandSocketClient(path: path).send(.tasks(nil)) == .tasks(scope))
    }

    @Test func theHandlerReceivesTheRequestIntact() async throws {
        let received = Received()
        let server = CommandSocketServer(path: path) { request in
            await received.set(request)
            return .refused("ok")
        }
        try server.start()
        defer { server.stop() }
        let add = CommandRequest.add(herdrAdd("Reply to co-advisor by fri 23:59"))

        _ = try CommandSocketClient(path: path).send(add)

        #expect(await received.request == add)
    }

    @Test func theSocketIsReadableOnlyByTheOwner() throws {
        let server = server()
        try server.start()
        defer { server.stop() }

        let mode = try #require(try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int)
        #expect(mode & 0o777 == 0o600)
    }

    @Test func withNoAppTheClientReportsNotRunning() {
        #expect(throws: CommandSocketClient.Failure.notRunning) {
            try CommandSocketClient(path: path).send(.tasks(nil))
        }
    }

    @Test func aSocketLeftByACrashIsReplaced() throws {
        let crashed = server()
        try crashed.start()
        crashed.stop(removingFile: false)
        #expect(throws: CommandSocketClient.Failure.notRunning) {
            try CommandSocketClient(path: path).send(.tasks(nil))
        }

        let restarted = server()
        try restarted.start()
        defer { restarted.stop() }
        #expect(try CommandSocketClient(path: path).send(.tasks(nil)) == .tasks(scope))
    }

    @Test func stoppingRemovesTheSocket() throws {
        let server = server()
        try server.start()
        server.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func aPathTooLongForASocketIsRejected() {
        let long = "/tmp/" + String(repeating: "x", count: 120)
        #expect(throws: CommandSocketServer.Failure.pathTooLong) { try CommandSocketServer(path: long) { _ in .refused("") }.start() }
        #expect(throws: CommandSocketClient.Failure.pathTooLong) { try CommandSocketClient(path: long).send(.tasks(nil)) }
    }
}

actor Received {
    var request: CommandRequest?
    func set(_ request: CommandRequest) { self.request = request }
}
