// Throwaway spike for issue #1. Safari starts this sandboxed appex for each
// browser.runtime.sendNativeMessage, whether or not the containing app is running. It never
// writes authoritative state: it reads the app's policy snapshot and appends to the inbox.
import SafariServices
import os.log

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any] ?? [:]
        let profile = (item?.userInfo?[SFExtensionProfileKey] as? UUID)?.uuidString ?? "none"
        let receivedAt = SharedStore.now()

        let probes = SharedStore.probeAll()
        var response: [String: Any] = [
            "handlerPid": Int(getpid()),
            "receivedAt": receivedAt,
            "stores": probes.map { $0.1.dictionary },
            "appended": 0,
        ]

        guard let location = probes.first(where: { $0.1.writable })?.0 else {
            response["ok"] = false
            response["error"] = "no writable shared store"
            os_log(.error, "FocusPilotSpikeS1: no writable shared store: %{public}@", String(describing: response["stores"]))
            return complete(context, response)
        }
        response["transport"] = location.transport

        let records = message["records"] as? [[String: Any]] ?? []
        let envelope: [String: Any] = [
            "receivedAt": receivedAt,
            "handlerPid": Int(getpid()),
            "transport": location.transport,
            "safariProfile": profile,
        ]
        var lines = records.map { envelope.merging(["kind": "observation", "payload": $0]) { a, _ in a } }
        lines.append(envelope.merging(["kind": "handler-request", "payload": [
            "type": message["type"] ?? "unknown",
            "reason": message["reason"] ?? "",
            "installId": message["installId"] ?? "",
            "workerInstance": message["workerInstance"] ?? "",
            "recordCount": records.count,
            "stores": probes.map { $0.1.dictionary },
        ]]) { a, _ in a })

        do {
            try SharedStore.appendLines(lines, to: location.url.appendingPathComponent(Spike.inboxFile))
            response["appended"] = records.count
            response["ok"] = true
        } catch {
            response["ok"] = false
            response["error"] = "append failed: \(error)"
        }
        if let policy = SharedStore.readJSON(location.url.appendingPathComponent(Spike.policyFile)) {
            response["policy"] = policy
        }
        if let command = SharedStore.readJSON(location.url.appendingPathComponent(Spike.commandFile)) {
            response["command"] = command
        }
        complete(context, response)
    }

    private func complete(_ context: NSExtensionContext, _ response: [String: Any]) {
        let item = NSExtensionItem()
        item.userInfo = [SFExtensionMessageKey: response]
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
}
