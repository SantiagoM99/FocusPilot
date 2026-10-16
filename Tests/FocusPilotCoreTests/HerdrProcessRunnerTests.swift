import Foundation
import Testing
@testable import FocusPilotCore

@Suite("Herdr process runner")
struct HerdrProcessRunnerTests {
    @Test func returnsTheChildsOutputAndStatus() async throws {
        let output = try await HerdrProcessRunner().run(executable: URL(fileURLWithPath: "/bin/echo"),
                                                        arguments: ["hello"], environment: [:])
        #expect(output.status == 0)
        #expect(String(decoding: output.standardOutput, as: UTF8.self) == "hello\n")
    }

    @Test func childSeesOnlyTheGivenEnvironment() async throws {
        let output = try await HerdrProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/env"),
                                                        arguments: [], environment: ["ONLY": "this"])
        #expect(String(decoding: output.standardOutput, as: UTF8.self) == "ONLY=this\n")
    }

    @Test func aChildThatHangsIsStopped() async {
        var runner = HerdrProcessRunner()
        runner.timeout = .milliseconds(200)
        await #expect(throws: HerdrProcessRunner.TimedOut.self) {
            try await runner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], environment: [:])
        }
    }

    @Test func aChildThatIgnoresTerminationIsKilled() async {
        var runner = HerdrProcessRunner()
        runner.timeout = .milliseconds(200)
        runner.killGrace = .milliseconds(200)
        let start = ContinuousClock.now
        await #expect(throws: HerdrProcessRunner.TimedOut.self) {
            // exec keeps one process, so the ignored SIGTERM applies to sleep itself.
            try await runner.run(executable: URL(fileURLWithPath: "/bin/sh"),
                                 arguments: ["-c", "trap '' TERM; exec /bin/sleep 10"], environment: [:])
        }
        #expect(ContinuousClock.now - start < .seconds(3))
    }

    @Test func oversizedOutputIsRejected() async {
        var runner = HerdrProcessRunner()
        runner.outputLimit = 1000
        await #expect(throws: HerdrProcessRunner.OutputTooLarge.self) {
            try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/yes"), arguments: [], environment: [:])
        }
    }
}
