// Throwaway spike for issue #1. A menu-bar-only app (LSUIElement) standing in for FocusPilot:
// it publishes the policy snapshot, imports the extension's inbox, and logs its own lifecycle so
// login launch, window close and quit can be told apart afterwards.
import AppKit
import Combine
import SafariServices
import ServiceManagement
import SwiftUI

// MARK: - Policy and stores

enum PolicyWriter {
    static let domain = "instagram.com"
    // S3 (issue #3) adds YouTube; exceptions name one of these domains, optionally one exact URL.
    static let domains = ["instagram.com", "youtube.com"]

    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    static func current() -> [String: Any]? {
        for (location, probe) in SharedStore.probeAll() where probe.writable {
            if let p = SharedStore.readJSON(location.url.appendingPathComponent(Spike.policyFile)) as? [String: Any] {
                return p
            }
        }
        return nil
    }

    static func session(mode: String, minutes: Double) -> [String: Any] {
        let now = Date()
        return [
            "sessionId": "session-\(Int(now.timeIntervalSince1970 * 1000))",
            "mode": mode,
            "startsAt": iso(now),
            "endsAt": iso(now.addingTimeInterval(minutes * 60)),
            "ended": false,
            "domains": domains,
            "exceptions": [[String: Any]](),
        ]
    }

    static func withException(minutes: Double, domain: String = domain, url: String? = nil) -> [String: Any]? {
        guard var policy = current(), var session = policy["session"] as? [String: Any] else { return nil }
        let expiresAt = Date().addingTimeInterval(minutes * 60)
        var exceptions = session["exceptions"] as? [[String: Any]] ?? []
        var exception: [String: Any] = ["id": "exc-\(Int(Date().timeIntervalSince1970 * 1000))", "domain": domain, "expiresAt": iso(expiresAt)]
        if let url { exception["url"] = url }
        exceptions.append(exception)
        session["exceptions"] = exceptions
        policy["session"] = session
        return policy
    }

    static func ended() -> [String: Any]? {
        guard var policy = current(), var session = policy["session"] as? [String: Any] else { return nil }
        session["ended"] = true
        policy["session"] = session
        return policy
    }

    // Writes the snapshot to every writable store so the handler finds it whichever transport it
    // ends up with. The revision is wall-clock milliseconds; the extension rejects lower ones.
    @discardableResult
    static func publish(session: Any?, base: [String: Any]? = nil) -> (revision: Int, written: [String], failed: [String]) {
        let revision = Int(Date().timeIntervalSince1970 * 1000)
        let policy: [String: Any] = [
            "schemaVersion": 1,
            "revision": revision,
            "writtenAt": iso(Date()),
            "writer": "FocusPilotSpikeS1.app pid \(getpid())",
            "alwaysOn": base?["alwaysOn"] ?? [Any](),
            "session": session ?? NSNull(),
        ]
        var written: [String] = [], failed: [String] = []
        for (location, probe) in SharedStore.probeAll() {
            guard probe.writable else { failed.append("\(location.transport): \(probe.error ?? "not writable")"); continue }
            do {
                try SharedStore.writeAtomically(policy, to: location.url.appendingPathComponent(Spike.policyFile))
                written.append(location.transport)
            } catch {
                failed.append("\(location.transport): \(error)")
            }
        }
        AppEvents.log("policy-published", ["revision": revision, "written": written, "failed": failed, "session": session ?? NSNull()])
        return (revision, written, failed)
    }
}

enum AppEvents {
    static func log(_ kind: String, _ details: [String: Any] = [:]) {
        let line: [String: Any] = ["at": SharedStore.now(), "kind": kind, "pid": Int(getpid()), "details": details]
        for (location, probe) in SharedStore.probeAll() where probe.writable {
            try? SharedStore.appendLines([line], to: location.url.appendingPathComponent(Spike.appEventsFile))
        }
    }
}

// MARK: - Command line (used by scripts/check.sh and scripts/policy.sh)

enum CLI {
    // Returns true if a CLI command ran and the process should exit.
    static func run(_ args: [String]) -> Bool {
        guard args.count > 1, args[1].hasPrefix("--") else { return false }
        func minutes(_ i: Int) -> Double { args.count > i ? Double(args[i]) ?? 1 : 1 }
        switch args[1] {
        case "--probe":
            let report = SharedStore.probeAll().map { $0.1.dictionary }
            print(String(data: try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
        case "--normal", "--strict":
            push(PolicyWriter.publish(session: PolicyWriter.session(mode: args[1] == "--strict" ? "strict" : "normal", minutes: minutes(2))))
        case "--exception":
            // --exception MIN [DOMAIN [URL]]: a URL-scoped exception leaves the rest of the domain blocked.
            guard let p = PolicyWriter.withException(minutes: minutes(2), domain: args.count > 3 ? args[3] : PolicyWriter.domain, url: args.count > 4 ? args[4] : nil)
            else { print("no session"); exit(2) }
            push(PolicyWriter.publish(session: p["session"], base: p))
        case "--end":
            guard let p = PolicyWriter.ended() else { print("no session"); exit(2) }
            push(PolicyWriter.publish(session: p["session"], base: p))
        case "--clear":
            push(PolicyWriter.publish(session: nil))
        case "--inspect-tabs", "--dnr-mode":
            // --dnr-mode redirect|block switches the DNR action for blocked domains (S3 comparison).
            let id = "cmd-\(Int(Date().timeIntervalSince1970 * 1000))"
            var cmd: [String: Any] = ["id": id, "action": args[1] == "--dnr-mode" ? "dnr-mode" : "inspect-tabs", "writtenAt": PolicyWriter.iso(Date())]
            if args[1] == "--dnr-mode" { cmd["mode"] = args.count > 2 ? args[2] : "redirect" }
            for (location, probe) in SharedStore.probeAll() where probe.writable {
                try? SharedStore.writeAtomically(cmd, to: location.url.appendingPathComponent(Spike.commandFile))
            }
            push((Int(Date().timeIntervalSince1970 * 1000), ["command"], []))
        case "--close-probe-tabs":
            // S3: asks the extension to close the tabs the spike opened (marked #fp-probe=…). No
            // AppleScript: the command rides the next native round trip, nudged by the push.
            let id = "cmd-\(Int(Date().timeIntervalSince1970 * 1000))"
            for (location, probe) in SharedStore.probeAll() where probe.writable {
                try? SharedStore.writeAtomically(["id": id, "action": "close-probe-tabs", "writtenAt": PolicyWriter.iso(Date())], to: location.url.appendingPathComponent(Spike.commandFile))
            }
            AppEvents.log("command", ["id": id, "action": "close-probe-tabs"])
            push((Int(Date().timeIntervalSince1970 * 1000), ["command"], []))
        case "--extension-state":
            var text = "pending"
            SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: Spike.extensionBundleID) { state, error in
                text = state.map { $0.isEnabled ? "enabled" : "installed, disabled" } ?? "not found: \(error.map { "\($0)" } ?? "nil")"
            }
            wait { text != "pending" }
            print(text)
        case "--login-status":
            print(SpikeModel.describe(SMAppService.mainApp.status))
        case "--unregister-login-item":
            do { try SMAppService.mainApp.unregister(); print("unregistered") } catch { print("unregister: \(error)") }
        default:
            print("usage: --probe | --normal MIN | --strict MIN | --exception MIN [DOMAIN [URL]] | --close-probe-tabs | --inspect-tabs | --dnr-mode redirect|block | --end | --clear | --extension-state | --login-status | --unregister-login-item")
            exit(2)
        }
        return true
    }

    // The same nudge the menu sends, from this short-lived process, so tests need no menu clicks.
    // Logged as "push" in app-events like the menu's; skipped when Safari is not running.
    private static func push(_ r: (revision: Int, written: [String], failed: [String])) {
        print(r)
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").isEmpty else {
            AppEvents.log("push-skipped", ["revision": r.revision, "why": "Safari not running", "from": "cli"])
            return
        }
        var done = false
        let sentAt = Date()
        SFSafariApplication.dispatchMessage(withName: "policy-changed", toExtensionWithIdentifier: Spike.extensionBundleID, userInfo: ["revision": r.revision]) { error in
            AppEvents.log("push", ["revision": r.revision, "from": "cli", "callbackMs": Int(Date().timeIntervalSince(sentAt) * 1000), "error": error.map { "\($0)" } ?? NSNull()])
            print("push: \(error.map { "\($0)" } ?? "ok")")
            done = true
        }
        wait { done }
    }

    private static func wait(timeout: TimeInterval = 10, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        if !condition() { print("timed out after \(timeout)s") }
    }
}

// MARK: - Model

@MainActor
final class SpikeModel: ObservableObject {
    static let shared = SpikeModel()

    @Published var probes: [StoreProbe] = []
    @Published var policySummary = "none"
    @Published var lastAck = "none yet"
    @Published var inboxStats = ""
    @Published var loginItem = ""
    @Published var extensionState = "unknown"
    @Published var lastAction = ""
    @Published var recentInbox: [String] = []
    private var timer: Timer?

    var menuIcon: String {
        guard let p = PolicyWriter.current(), let s = p["session"] as? [String: Any], s["ended"] as? Bool == false else { return "shield" }
        return "shield.lefthalf.filled"
    }

    func start() {
        importInbox(reason: "launch")
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in SpikeModel.shared.refresh() }
        }
    }

    func refresh() {
        probes = SharedStore.probeAll().map { $0.1 }
        if let p = PolicyWriter.current() {
            let s = p["session"] as? [String: Any]
            let exc = (s?["exceptions"] as? [[String: Any]] ?? []).map { "\($0["expiresAt"] ?? "")" }.joined(separator: ", ")
            policySummary = s.map { "rev \(p["revision"] ?? "?") \($0["mode"] ?? "") ends \($0["endsAt"] ?? "") ended=\($0["ended"] ?? "") exceptions=[\(exc)]" } ?? "rev \(p["revision"] ?? "?") no session"
        } else {
            policySummary = "none"
        }
        loginItem = Self.describe(SMAppService.mainApp.status)
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: Spike.extensionBundleID) { state, error in
            let text = state.map { $0.isEnabled ? "enabled" : "installed, disabled" } ?? "not found: \(error.map { "\($0)" } ?? "nil")"
            Task { @MainActor in SpikeModel.shared.extensionState = text }
        }
        readInboxTail()
    }

    static func describe(_ s: SMAppService.Status) -> String {
        switch s {
        case .notRegistered: "notRegistered"
        case .enabled: "enabled"
        case .requiresApproval: "requiresApproval"
        case .notFound: "notFound"
        @unknown default: "unknown(\(s.rawValue))"
        }
    }

    private func inboxURLs() -> [URL] {
        SharedStore.probeAll().filter { $0.1.writable }.map { $0.0.url.appendingPathComponent(Spike.inboxFile) }
    }

    private func readInboxTail() {
        var lines: [String] = []
        for url in inboxURLs() {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            lines += text.split(separator: "\n").suffix(400).map(String.init)
        }
        let records = lines.compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        if let ack = records.last(where: { (($0["payload"] as? [String: Any])?["kind"] as? String) == "ack" || (($0["payload"] as? [String: Any])?["kind"] as? String) == "reconcile" }),
           let p = ack["payload"] as? [String: Any] {
            lastAck = "\(p["kind"] ?? "") rev \(p["revision"] ?? "nil") blocked=\(p["blockedDomains"] ?? "") via \(ack["transport"] ?? "") at \(ack["receivedAt"] ?? "")"
        }
        recentInbox = records.suffix(12).map { r in
            let p = r["payload"] as? [String: Any] ?? [:]
            return "\(r["receivedAt"] ?? "") \(r["kind"] ?? "") \(p["kind"] ?? p["reason"] ?? "") rev=\(p["revision"] ?? "-")"
        }
    }

    // Step 3 of the cross-process contract: import and deduplicate by (installId, seq). The seen
    // set lives in UserDefaults, which is enough for a spike.
    func importInbox(reason: String) {
        var seen = Set(UserDefaults.standard.stringArray(forKey: "seenObservations") ?? [])
        var new = 0, duplicates = 0, other = 0
        for url in inboxURLs() {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") {
                guard let r = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
                guard r["kind"] as? String == "observation", let p = r["payload"] as? [String: Any],
                      let install = p["installId"] as? String, let seq = p["seq"] else { other += 1; continue }
                let key = "\(install)#\(seq)"
                if seen.insert(key).inserted { new += 1 } else { duplicates += 1 }
            }
        }
        UserDefaults.standard.set(Array(seen), forKey: "seenObservations")
        inboxStats = "import(\(reason)): \(new) new, \(duplicates) already seen, \(other) handler lines, \(seen.count) total"
        AppEvents.log("inbox-import", ["reason": reason, "new": new, "alreadySeen": duplicates, "handlerLines": other])
    }

    func publish(session: Any?, base: [String: Any]? = nil) {
        let r = PolicyWriter.publish(session: session, base: base)
        lastAction = "published rev \(r.revision) to \(r.written) failed \(r.failed)"
        pushToSafari(revision: r.revision)
        refresh()
    }

    // dispatchMessage launches Safari if it is not running, which would spoil the restart tests,
    // so only nudge a Safari that is already open.
    func pushToSafari(revision: Int) {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").isEmpty else {
            AppEvents.log("push-skipped", ["revision": revision, "why": "Safari not running"])
            return
        }
        SFSafariApplication.dispatchMessage(withName: "policy-changed", toExtensionWithIdentifier: Spike.extensionBundleID, userInfo: ["revision": revision]) { error in
            AppEvents.log("push", ["revision": revision, "error": error.map { "\($0)" } ?? NSNull()])
        }
    }

    func startSession(_ mode: String, minutes: Double) {
        publish(session: PolicyWriter.session(mode: mode, minutes: minutes))
    }

    func grantException(minutes: Double) {
        guard let p = PolicyWriter.withException(minutes: minutes) else { lastAction = "no session to add an exception to"; return }
        publish(session: p["session"], base: p)
    }

    func endSession() {
        guard let p = PolicyWriter.ended() else { lastAction = "no session"; return }
        publish(session: p["session"], base: p)
    }

    func setLoginItem(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            lastAction = "login item \(on ? "register" : "unregister") ok"
        } catch {
            lastAction = "login item \(on ? "register" : "unregister") failed: \(error)"
        }
        AppEvents.log("login-item", ["register": on, "result": lastAction, "status": Self.describe(SMAppService.mainApp.status)])
        refresh()
    }
}

// MARK: - App and lifecycle

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var sigterm: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Lets scripts quit the app with `kill -TERM` and still get a normal terminate (and its
        // app-terminate event) without Apple Events, which would need Automation consent.
        signal(SIGTERM, SIG_IGN)
        sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigterm?.setEventHandler {
            AppEvents.log("sigterm")
            NSApp.terminate(nil)
        }
        sigterm?.resume()
        let event = NSAppleEventManager.shared().currentAppleEvent
        let loginLaunch = event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        AppEvents.log("app-launch", [
            "launchedAsLogInItem": loginLaunch,
            "bundlePath": Bundle.main.bundlePath,
            "loginItemStatus": SpikeModel.describe(SMAppService.mainApp.status),
            "parentPid": Int(getppid()),
        ])
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in AppEvents.log("will-sleep") }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            AppEvents.log("did-wake")
            Task { @MainActor in SpikeModel.shared.importInbox(reason: "wake") }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            guard let w = note.object as? NSWindow, w.title.contains("Spike") else { return }
            AppEvents.log("window-close", ["title": w.title])
        }
        Task { @MainActor in SpikeModel.shared.start() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        AppEvents.log("app-terminate")
    }
}

@main
struct FocusPilotSpikeS1App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = SpikeModel.shared

    init() {
        if CLI.run(CommandLine.arguments) { exit(0) }
    }

    var body: some Scene {
        MenuBarExtra("FocusPilot S1", systemImage: model.menuIcon) {
            MenuContent().environmentObject(model)
        }
        Window("FocusPilot Spike S1", id: "main") {
            MainWindow().environmentObject(model)
        }
        .defaultLaunchBehavior(.suppressed)
    }
}

struct MenuContent: View {
    @EnvironmentObject var model: SpikeModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Policy: \(model.policySummary)")
        Text("Last ack: \(model.lastAck)")
        Text("Extension: \(model.extensionState) · Login item: \(model.loginItem)")
        Divider()
        Button("Start normal session · 2 min") { model.startSession("normal", minutes: 2) }
        Button("Start normal session · 5 min") { model.startSession("normal", minutes: 5) }
        Button("Start normal session · 15 min") { model.startSession("normal", minutes: 15) }
        Button("Start strict session · 2 min") { model.startSession("strict", minutes: 2) }
        Button("Grant exception · 1 min") { model.grantException(minutes: 1) }
        Button("Grant exception · 2 min") { model.grantException(minutes: 2) }
        Button("End session") { model.endSession() }
        Button("Clear policy") { model.publish(session: nil) }
        Divider()
        Button("Open window…") {
            AppEvents.log("window-open-request")
            openWindow(id: "main")
            NSApp.activate()
        }
        Button("Open Safari extension settings") {
            SFSafariApplication.showPreferencesForExtension(withIdentifier: Spike.extensionBundleID) { error in
                if let error { AppEvents.log("show-preferences-failed", ["error": "\(error)"]) }
            }
        }
        Button("Import inbox now") { model.importInbox(reason: "menu") }
        Divider()
        Button("Quit FocusPilot Spike S1") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

struct MainWindow: View {
    @EnvironmentObject var model: SpikeModel
    @State private var sessionMinutes = 5.0
    @State private var exceptionMinutes = 1.0

    var body: some View {
        Form {
            Section("Shared stores") {
                ForEach(model.probes, id: \.transport) { p in
                    Text("\(p.transport): \(p.writable ? "writable" : "NOT writable") \(p.path)\(p.error.map { "\n\($0)" } ?? "")")
                        .font(.caption.monospaced()).textSelection(.enabled)
                }
            }
            Section("Policy") {
                Text(model.policySummary).font(.caption.monospaced()).textSelection(.enabled)
                Stepper("Session minutes: \(sessionMinutes, specifier: "%.0f")", value: $sessionMinutes, in: 1...240)
                HStack {
                    Button("Start normal") { model.startSession("normal", minutes: sessionMinutes) }
                    Button("Start strict") { model.startSession("strict", minutes: sessionMinutes) }
                    Button("End session") { model.endSession() }
                    Button("Clear") { model.publish(session: nil) }
                }
                Stepper("Exception minutes: \(exceptionMinutes, specifier: "%.0f")", value: $exceptionMinutes, in: 1...60)
                Button("Grant exception") { model.grantException(minutes: exceptionMinutes) }
            }
            Section("Extension and inbox") {
                Text("Safari extension: \(model.extensionState)")
                Text("Last ack: \(model.lastAck)").textSelection(.enabled)
                Text(model.inboxStats)
                ForEach(Array(model.recentInbox.enumerated()), id: \.offset) { Text($0.element).font(.caption2.monospaced()) }
            }
            Section("Login item") {
                Text("SMAppService.mainApp.status: \(model.loginItem)")
                HStack {
                    Button("Register") { model.setLoginItem(true) }
                    Button("Unregister") { model.setLoginItem(false) }
                    Button("Open Login Items settings") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
            Text(model.lastAction).font(.caption).textSelection(.enabled)
        }
        .formStyle(.grouped)
        .frame(minWidth: 620, minHeight: 640)
        .onAppear {
            AppEvents.log("window-open")
            model.refresh()
        }
    }
}
