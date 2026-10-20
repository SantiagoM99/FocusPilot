import Foundation
import Testing
@testable import FocusPilotCore

/// Runs the built focuspilot-chrome-host the way Chrome does: origin as the
/// argument, framed messages on stdin, answers on stdout while stdin stays
/// open, exit when it closes.
@Suite("Chrome host executable")
struct ChromeHostProcessTests {
    private var executable: URL {
        // Built next to the test bundle.
        let products = Bundle(for: HostHarness.self).bundleURL.deletingLastPathComponent()
        return products.appending(path: "focuspilot-chrome-host")
    }

    private func launch(origin: String, data: URL) throws -> (Process, Pipe, Pipe) {
        let process = Process()
        process.executableURL = executable
        process.arguments = [origin]
        process.environment = ["FOCUSPILOT_DATA_DIR": data.path]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        return (process, input, output)
    }

    @Test(.timeLimit(.minutes(1))) func itAnswersHelloWhileThePortIsOpenAndExitsWhenItCloses() async throws {
        let data = try makeTemporaryDirectory()
        let (process, input, output) = try launch(origin: ChromeExtension.origin, data: data)
        let hello = try JSONSerialization.data(withJSONObject: ["type": "hello", "profileId": HostHarness.profile])
        try input.fileHandleForWriting.write(contentsOf: NativeMessageFrame.encode(hello))

        // Read the status frame while stdin is still open.
        let reply = try await Task.detached {
            var reader = NativeMessageReader()
            while true {
                let chunk = output.fileHandleForReading.availableData
                if chunk.isEmpty { return nil as Data? }
                if let first = try reader.append(chunk).first { return first }
            }
        }.value
        let message = try #require(reply.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(message["type"] as? String == "status")
        #expect(process.isRunning)

        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test func anotherOriginIsRefused() throws {
        let (process, _, _) = try launch(origin: "chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/", data: try makeTemporaryDirectory())

        process.waitUntilExit()

        #expect(process.terminationStatus == 1)
    }
}
