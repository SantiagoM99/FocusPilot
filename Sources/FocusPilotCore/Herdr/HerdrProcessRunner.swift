import Foundation

public struct HerdrProcessOutput: Sendable {
    public var status: Int32
    public var standardOutput: Data

    public init(status: Int32, standardOutput: Data) {
        self.status = status
        self.standardOutput = standardOutput
    }
}

public protocol HerdrProcessRunning: Sendable {
    func run(executable: URL, arguments: [String], environment: [String: String]) async throws -> HerdrProcessOutput
}

/// Runs a child process with exactly the given environment, giving up after
/// `timeout` and reading at most `outputLimit` bytes of its output.
public struct HerdrProcessRunner: HerdrProcessRunning {
    public var timeout: Duration = .seconds(3)
    public var outputLimit = 1 << 20

    public init() {}

    public struct OutputTooLarge: Error {}
    /// The child was stopped by a signal, normally the timeout's.
    public struct TimedOut: Error {}

    public func run(executable: URL, arguments: [String], environment: [String: String]) async throws -> HerdrProcessOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let exited = AsyncStream<Void> { continuation in
            process.terminationHandler = { _ in continuation.finish() }
        }
        try process.run()
        let timeout = timeout
        let watchdog = Task {
            try await Task.sleep(for: timeout)
            process.terminate()
        }
        defer { watchdog.cancel() }

        let limit = outputLimit
        let data = try await Task.detached {
            var data = Data()
            while let chunk = try output.fileHandleForReading.read(upToCount: 64 * 1024), !chunk.isEmpty {
                data.append(chunk)
                if data.count > limit {
                    process.terminate()
                    throw OutputTooLarge()
                }
            }
            return data
        }.value
        for await _ in exited {}
        // Only the watchdog stops the child with a signal.
        if process.terminationReason == .uncaughtSignal { throw TimedOut() }
        return HerdrProcessOutput(status: process.terminationStatus, standardOutput: data)
    }
}
