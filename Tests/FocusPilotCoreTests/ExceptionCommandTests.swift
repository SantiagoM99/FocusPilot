import Darwin
import Foundation
import Testing
@testable import FocusPilotCore

/// Records exception requests and answers with a canned outcome.
private actor GateDouble: ExceptionGate {
    var requests: [ExceptionCommand] = []
    var cancels = 0
    var answer: Result<ExceptionOutcome, ExceptionError> = .success(.needsConfirmation)

    func set(_ answer: Result<ExceptionOutcome, ExceptionError>) { self.answer = answer }

    func requestException(_ scope: ExceptionScope, duration: TimeInterval, reason: String?, confirmed: Bool) async throws -> ExceptionOutcome {
        requests.append(ExceptionCommand(scope: scope, duration: duration, reason: reason, confirmed: confirmed))
        return try answer.get()
    }

    func cancelException() async { cancels += 1 }
}

@Suite("Exception requests over the command socket")
struct ExceptionCommandTests {
    private let host = CommandPeer(processID: 77, executablePath: "/Applications/FocusPilot.app/Contents/Helpers/focuspilot-chrome-host")
    private let cli = CommandPeer(processID: 78, executablePath: "/Applications/FocusPilot.app/Contents/Helpers/focuspilot")
    private let gate = GateDouble()
    private let service: CommandService
    private let lecture = ExceptionCommand(scope: .page(url: "https://youtube.com/watch?v=1"), duration: 600, reason: nil, confirmed: false)

    init() throws {
        let repository = try TaskRepository(location: StorageLocation(directory: makeTemporaryDirectory()), now: { wednesdayMorningInBogota })
        service = CommandService(repository: repository, exceptions: gate,
                                 exceptionCaller: "/Applications/FocusPilot.app/Contents/Helpers/focuspilot-chrome-host")
    }

    @Test func theChromeHostsRequestReachesTheCoordinator() async {
        let granted = wednesdayMorningInBogota.addingTimeInterval(600)
        await gate.set(.success(.granted(expiresAt: granted)))

        #expect(await service.handle(.exception(lecture), from: host) == .exception(.granted(expiresAt: granted)))
        #expect(await gate.requests == [lecture])
    }

    /// Agents in Herdr panes reach the same socket through the focuspilot
    /// command; only the Chrome host, which the blocked page talks to, may ask.
    @Test func anyOtherCallerIsRefusedAndNothingIsAsked() async {
        for peer in [cli, CommandPeer(processID: 79, executablePath: nil), nil] {
            #expect(await service.handle(.exception(lecture), from: peer) == .refused(CommandService.exceptionCallerMessage))
            #expect(await service.handle(.cancelException, from: peer) == .refused(CommandService.exceptionCallerMessage))
        }
        #expect(await gate.requests.isEmpty)
        #expect(await gate.cancels == 0)
    }

    @Test func refusalsComeBackInWords() async {
        await gate.set(.failure(.notBlocked("example.com")))
        #expect(await service.handle(.exception(lecture), from: host) == .refused("example.com isn't blocked by any rule."))
        await gate.set(.failure(.reasonRequired))
        #expect(await service.handle(.exception(lecture), from: host) == .refused("Say why you need it for the task."))
    }

    @Test func cancellingReachesTheCoordinator() async {
        #expect(await service.handle(.cancelException, from: host) == .exceptionCancelled)
        #expect(await gate.cancels == 1)
    }

    @Test func requestsAndAnswersSurviveTheWire() throws {
        let request = CommandRequest.exception(ExceptionCommand(scope: .site(domain: "youtube.com"), duration: 300, reason: "Lecture", confirmed: true))
        #expect(try JSONDecoder().decode(CommandRequest.self, from: JSONEncoder().encode(request)) == request)
        for outcome in [ExceptionOutcome.granted(expiresAt: wednesdayMorningInBogota), .needsConfirmation, .waitUntil(wednesdayMorningInBogota)] {
            let response = CommandResponse.exception(outcome)
            #expect(try JSONDecoder().decode(CommandResponse.self, from: JSONEncoder().encode(response)) == response)
        }
    }
}

@Suite("Command socket peers")
final class CommandPeerTests {
    private let directory: URL

    init() throws { directory = try makeShortDirectory() }
    deinit { try? FileManager.default.removeItem(at: directory) }

    @Test func theHandlerLearnsWhichProcessIsCalling() throws {
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
        #expect(peer.processID == getpid())
        #expect(peer.executablePath == CommandPeer.executablePath(of: getpid()))
        #expect(peer.executablePath?.hasPrefix("/") == true)
    }
}
