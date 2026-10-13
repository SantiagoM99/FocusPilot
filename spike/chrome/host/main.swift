// Throwaway spike for issue #2: Chrome native messaging host.
// Protocol: https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging
// Each message is a UInt32 length in native byte order followed by UTF-8 JSON.
// Host -> Chrome messages are limited to 1 MB.

import CryptoKit
import Foundation

let allowedOrigin = "chrome-extension://nnebgihjjgaokjddhlkfmijogibdpfjj/"
let maxOutgoingBytes = 1024 * 1024

let dataDir = URL(fileURLWithPath: NSHomeDirectory())
    .appendingPathComponent("Library/Application Support/FocusPilotSpike", isDirectory: true)
let policyURL = dataDir.appendingPathComponent("policy.json")
let inboxURL = dataDir.appendingPathComponent("inbox.jsonl")

let hostInstance = UUID().uuidString
let hostPid = ProcessInfo.processInfo.processIdentifier
let callerOrigin = CommandLine.arguments.dropFirst().first ?? ""
let isoFormatter = ISO8601DateFormatter()
isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

let inboxQueue = DispatchQueue(label: "inbox")
let stdoutQueue = DispatchQueue(label: "stdout")

func appendInbox(kind: String, payload: Any?) {
    var record: [String: Any] = [
        "receivedAt": isoFormatter.string(from: Date()),
        "kind": kind,
        "hostPid": hostPid,
        "hostInstance": hostInstance,
        "origin": callerOrigin,
        "executable": CommandLine.arguments[0],
    ]
    if let payload { record["payload"] = payload }
    inboxQueue.sync {
        guard var line = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: inboxURL) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: inboxURL)
        }
    }
}

func send(_ object: [String: Any]) {
    guard let body = try? JSONSerialization.data(withJSONObject: object) else { return }
    guard body.count <= maxOutgoingBytes else {
        appendInbox(kind: "host-error", payload: ["error": "outgoing message too large", "bytes": body.count])
        return
    }
    var length = UInt32(body.count)
    stdoutQueue.sync {
        let header = Data(bytes: &length, count: 4)
        FileHandle.standardOutput.write(header + body)
    }
}

try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

// Chrome already enforces allowed_origins in the host manifest; this is defence in depth
// and lets the spike show that a manual launch with a foreign origin is refused.
guard callerOrigin == allowedOrigin else {
    appendInbox(kind: "rejected-origin", payload: ["arguments": CommandLine.arguments])
    exit(1)
}

appendInbox(kind: "host-start", payload: ["arguments": CommandLine.arguments])

// Policy file watcher: polling keeps the spike simple and survives editors that replace the file.
var lastSentChecksum: String?
func pushPolicyIfChanged(force: Bool) {
    guard let bytes = try? Data(contentsOf: policyURL) else { return }
    let checksum = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    if !force && checksum == lastSentChecksum { return }
    guard let policy = try? JSONSerialization.jsonObject(with: bytes) else {
        appendInbox(kind: "host-error", payload: ["error": "policy.json is not valid JSON"])
        return
    }
    lastSentChecksum = checksum
    send(["type": "policy", "checksum": checksum, "sentAt": isoFormatter.string(from: Date()), "policy": policy])
    appendInbox(kind: "policy-sent", payload: ["checksum": checksum])
}

let policyQueue = DispatchQueue(label: "policy")
let policyTimer = DispatchSource.makeTimerSource(queue: policyQueue)
policyTimer.schedule(deadline: .now() + 1, repeating: 1)
policyTimer.setEventHandler { pushPolicyIfChanged(force: false) }
policyTimer.resume()

func readExactly(_ count: Int) -> Data? {
    var data = Data()
    while data.count < count {
        let chunk = FileHandle.standardInput.readData(ofLength: count - data.count)
        if chunk.isEmpty { return nil }
        data.append(chunk)
    }
    return data
}

// Stdin closes when the extension disconnects or Chrome exits; the host must then exit.
Thread.detachNewThread {
    while let header = readExactly(4) {
        let length = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        guard let body = readExactly(Int(length)) else { break }
        let message = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        appendInbox(kind: "extension-message", payload: message ?? ["unparsed": String(decoding: body, as: UTF8.self)])
        if message?["type"] as? String == "hello" {
            policyQueue.async { pushPolicyIfChanged(force: true) }
        }
    }
    appendInbox(kind: "host-stop", payload: ["reason": "stdin closed"])
    exit(0)
}

signal(SIGTERM, SIG_IGN)
let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termSource.setEventHandler {
    appendInbox(kind: "host-stop", payload: ["reason": "SIGTERM"])
    exit(0)
}
termSource.resume()

dispatchMain()
