import Foundation
import FocusPilotCore

// Chrome's native messaging host for FocusPilot, at
// FocusPilot.app/Contents/Helpers/focuspilot-chrome-host. Chrome starts one
// per profile when the extension connects and closes stdin when it leaves.
// The logic is ChromeHost in FocusPilotCore; this file is only the I/O.

guard CommandLine.arguments.count > 1, ChromeHost.accepts(origin: CommandLine.arguments[1]) else { exit(1) }

/// The host and its process lifetime. Everything runs on the main queue:
/// Swift checks main-actor isolation at run time.
@MainActor
final class HostProcess {
    private let host: ChromeHost

    init(location: StorageLocation, appBundle: URL?) {
        let output = FileHandle.standardOutput
        host = ChromeHost(location: location, environment: ChromeHost.Environment(
            isAppRunning: { CommandSocketClient(path: location.commandSocketPath).isListening() },
            openApp: {
                guard let appBundle else { return }
                let open = Process()
                open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                open.arguments = [appBundle.path]
                try? open.run()
            },
            now: { .now },
            processID: ProcessInfo.processInfo.processIdentifier,
            send: { body in
                guard let frame = try? NativeMessageFrame.encode(body) else { return }
                try? output.write(contentsOf: frame)
            }))
    }

    func receive(_ message: Data) { host.receive(message) }
    func poll() { host.poll() }

    func finish() -> Never {
        host.stop()
        exit(0)
    }
}

/// FocusPilot.app, when this host runs from inside it.
let appBundle: URL? = {
    let app = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return app.pathExtension == "app" ? app : nil
}()
let process = HostProcess(location: .applicationSupport(), appBundle: appBundle)

let timer = DispatchSource.makeTimerSource(queue: .main)
timer.schedule(deadline: .now() + 1, repeating: 1)
timer.setEventHandler { MainActor.assumeIsolated { process.poll() } }
timer.resume()

signal(SIGTERM, SIG_IGN)
let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
terminate.setEventHandler { MainActor.assumeIsolated { process.finish() } }
terminate.resume()

// Stdin closes when the extension disconnects or Chrome quits.
Thread.detachNewThread { [process] in
    var reader = NativeMessageReader()
    // availableData returns as soon as anything arrives (read(upToCount:)
    // waits for the full count) and is empty only at end of input.
    while case let chunk = FileHandle.standardInput.availableData, !chunk.isEmpty {
        guard let messages = try? reader.append(chunk) else { break }
        for message in messages {
            DispatchQueue.main.async { MainActor.assumeIsolated { process.receive(message) } }
        }
    }
    DispatchQueue.main.async { MainActor.assumeIsolated { process.finish() } }
}

dispatchMain()
