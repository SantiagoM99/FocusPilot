// Throwaway spike S4 probe. Default mode is READ-ONLY: `herdr --version`, `status`,
// `session list`, `agent list|get|read` and raw-socket `ping` / `agent.list`.
// `focus` mode (owner-approved 2026-10-16) runs exactly one `tab focus` or `agent focus`
// on the scratch agent `s4-scratch`, then restores the owner's tab. Never add
// prompt/send-keys/start/split/create/close/rename/move/attach/stop.
import AppKit
import Darwin
import Foundation

let home = FileManager.default.homeDirectoryForCurrentUser.path
let logDir = home + "/Library/Logs/FocusPilotHerdrProbe"
let focusMode = CommandLine.arguments.dropFirst().first == "focus"
let logPath = logDir + (focusMode ? "/focus.log" : "/probe.log")

// MARK: - Logging

final class Log {
    private let handle: FileHandle
    init() {
        try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logPath) || !focusMode {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        handle = FileHandle(forWritingAtPath: logPath)!
        handle.seekToEndOfFile()
    }
    func line(_ s: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        handle.write("[\(stamp)] \(s)\n".data(using: .utf8)!)
    }
}
let log = Log()

// MARK: - Process runner with explicit environment

/// Minimal environment for children. Deliberately contains no HERDR_* variables,
/// so whatever endpoint herdr picks comes from its own default resolution or flags.
let childEnv: [String: String] = [
    "HOME": home,
    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
    "LANG": "en_US.UTF-8",
]

struct RunResult {
    var status: Int32
    var stdout: Data
    var stderr: Data
    var wallMs: Double
    var childCpuMs: Double
    var out: String { String(decoding: stdout, as: UTF8.self) }
    var err: String { String(decoding: stderr, as: UTF8.self) }
}

func childCpuMs() -> Double {
    var ru = rusage()
    getrusage(RUSAGE_CHILDREN, &ru)
    func ms(_ t: timeval) -> Double { Double(t.tv_sec) * 1000 + Double(t.tv_usec) / 1000 }
    return ms(ru.ru_utime) + ms(ru.ru_stime)
}

func run(_ exe: String, _ args: [String], env: [String: String] = childEnv) -> RunResult {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    p.environment = env
    p.standardInput = FileHandle.nullDevice
    let outPipe = Pipe(), errPipe = Pipe()
    p.standardOutput = outPipe
    p.standardError = errPipe
    var outData = Data(), errData = Data()
    let group = DispatchGroup()
    let cpu0 = childCpuMs()
    let t0 = DispatchTime.now()
    do { try p.run() } catch {
        return RunResult(status: -1, stdout: Data(), stderr: "\(error)".data(using: .utf8)!, wallMs: 0, childCpuMs: 0)
    }
    group.enter()
    DispatchQueue.global().async { outData = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
    group.enter()
    DispatchQueue.global().async { errData = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
    p.waitUntilExit()
    group.wait()
    let wall = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e6
    return RunResult(status: p.terminationStatus, stdout: outData, stderr: errData,
                     wallMs: wall, childCpuMs: childCpuMs() - cpu0)
}

func trunc(_ s: String, _ n: Int = 400) -> String {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.count > n ? String(t.prefix(n)) + "…(\(t.count) chars)" : t
}

/// CLI output is untrusted text: parse as JSON object, never execute or interpolate it.
func json(_ d: Data) -> [String: Any]? {
    guard d.count < 8_000_000 else { return nil }
    return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
}

// MARK: - Raw socket client (newline-delimited JSON over a Unix domain socket)

func rawRequest(socketPath: String, _ request: String) -> (Data?, Double, String?) {
    let t0 = DispatchTime.now()
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return (nil, 0, "socket() errno \(errno)") }
    defer { close(fd) }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(socketPath.utf8)
    guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return (nil, 0, "path too long") }
    withUnsafeMutableBytes(of: &addr.sun_path) { buf in
        for (i, b) in pathBytes.enumerated() { buf[i] = b }
    }
    let rc = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard rc == 0 else { return (nil, 0, "connect() errno \(errno): \(String(cString: strerror(errno)))") }
    var tv = timeval(tv_sec: 5, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    let req = Array((request + "\n").utf8)
    guard write(fd, req, req.count) == req.count else { return (nil, 0, "write errno \(errno)") }
    var data = Data()
    var buf = [UInt8](repeating: 0, count: 65536)
    while true {
        let n = read(fd, &buf, buf.count)
        if n <= 0 { break }
        data.append(contentsOf: buf[0..<n])
        if buf[n - 1] == 0x0A { break }
        if data.count > 8_000_000 { break }
    }
    let wall = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e6
    return (data, wall, nil)
}

// MARK: - Probe steps

func logEnvironment() {
    let env = ProcessInfo.processInfo.environment
    log.line("== App launch environment ==")
    log.line("env keys: \(env.keys.sorted().joined(separator: ","))")
    log.line("PATH=\(env["PATH"] ?? "<unset>")")
    let herdrKeys = env.keys.filter { $0.hasPrefix("HERDR") }
    log.line("HERDR_* in app env: \(herdrKeys.isEmpty ? "none" : herdrKeys.joined(separator: ","))")
    log.line("parent pid=\(getppid()) (1 = launchd, i.e. not a terminal child)")
}

func resolveBinary() -> String? {
    log.line("== Binary resolution ==")
    // 1. Bare name through the app's own PATH: expected to fail for GUI apps.
    let viaEnv = run("/usr/bin/env", ["herdr", "--version"], env: ProcessInfo.processInfo.environment)
    log.line("/usr/bin/env herdr --version with app PATH -> status \(viaEnv.status) out=\(trunc(viaEnv.out)) err=\(trunc(viaEnv.err))")
    // 2. Fixed candidate list (install locations), no PATH.
    let candidates = [home + "/.local/bin/herdr", "/opt/homebrew/bin/herdr", "/usr/local/bin/herdr", home + "/.cargo/bin/herdr"]
    var found: String?
    for c in candidates {
        let ok = FileManager.default.isExecutableFile(atPath: c)
        log.line("candidate \(c): \(ok ? "executable" : "absent")")
        if ok && found == nil { found = c }
    }
    // 3. Login-shell lookup, for comparison only (runs user rc files; slower, fragile).
    let shell = run("/bin/zsh", ["-lc", "command -v herdr"], env: ["HOME": home])
    log.line("zsh -lc 'command -v herdr' -> status \(shell.status) out=\(trunc(shell.out)) wall=\(fmt(shell.wallMs))ms")
    guard let bin = found else { log.line("RESULT: no herdr binary found"); return nil }
    let resolved = (try? FileManager.default.destinationOfSymbolicLink(atPath: bin)) ?? bin
    log.line("RESULT: using \(bin) (symlink target: \(resolved))")
    let v = run(bin, ["--version"])
    log.line("\(bin) --version -> status \(v.status) out=\(trunc(v.out)) wall=\(fmt(v.wallMs))ms")
    return bin
}

struct Endpoint { var session: String; var socket: String; var serverPid: Int32?; var serverStart: String?; var sessionFlagMatches = false }

func fmt(_ d: Double) -> String { String(format: "%.1f", d) }

func serverProcess(socket: String) -> (Int32, String)? {
    let l = run("/usr/sbin/lsof", ["-t", socket])
    for pidStr in l.out.split(separator: "\n") {
        guard let pid = Int32(pidStr.trimmingCharacters(in: .whitespaces)) else { continue }
        let ps = run("/bin/ps", ["-o", "lstart=,command=", "-p", String(pid)])
        let line = ps.out.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasSuffix("herdr server") { return (pid, String(line.prefix(24))) }
    }
    return nil
}

func serverCpuSeconds(_ pid: Int32) -> Double? {
    let ps = run("/bin/ps", ["-o", "time=", "-p", String(pid)])
    // format [[hh:]mm:]ss.cc
    let parts = ps.out.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":").compactMap { Double($0) }
    guard !parts.isEmpty else { return nil }
    return parts.reduce(0) { $0 * 60 + $1 }
}

func resolveEndpoint(_ bin: String) -> Endpoint? {
    log.line("== Endpoint resolution (no HERDR_* env) ==")
    let st = run(bin, ["status", "--json"])
    log.line("status --json -> status \(st.status) wall=\(fmt(st.wallMs))ms err=\(trunc(st.err))")
    var socketFromStatus: String?
    if let j = json(st.stdout) {
        let c = j["client"] as? [String: Any] ?? [:]
        let s = j["server"] as? [String: Any] ?? [:]
        socketFromStatus = s["socket"] as? String
        log.line("client version=\(c["version"] ?? "?") protocol=\(c["protocol"] ?? "?") session=\(c["session"] ?? "nil")")
        log.line("server running=\(s["running"] ?? "?") version=\(s["version"] ?? "?") protocol=\(s["protocol"] ?? "?") compatible=\(s["compatible"] ?? "?") socket=\(socketFromStatus ?? "?")")
        let proto = s["protocol"] as? Int
        log.line("VERSION CHECK: server protocol \(proto.map(String.init) ?? "?") \(proto == 22 ? "== expected 22 OK" : "!= expected 22 -> refuse")")
    } else { log.line("status output not JSON: \(trunc(st.out))") }

    let sl = run(bin, ["session", "list", "--json"])
    log.line("session list --json -> status \(sl.status) wall=\(fmt(sl.wallMs))ms")
    var chosen: Endpoint?
    if let j = json(sl.stdout), let sessions = j["sessions"] as? [[String: Any]] {
        for s in sessions {
            let name = s["name"] as? String ?? "?"
            let sock = s["socket_path"] as? String ?? "?"
            log.line("session name=\(name) default=\(s["default"] ?? "?") running=\(s["running"] ?? "?") socket=\(sock)")
            if (s["default"] as? Bool) == true && (s["running"] as? Bool) == true {
                chosen = Endpoint(session: name, socket: sock, serverPid: nil, serverStart: nil)
            }
        }
    }
    guard var ep = chosen else { log.line("RESULT: no running default session"); return nil }
    log.line("socket from status == socket from session list: \(socketFromStatus == ep.socket)")
    if let (pid, start) = serverProcess(socket: ep.socket) {
        ep.serverPid = pid; ep.serverStart = start
        log.line("server process pid=\(pid) started=\(start) (instance identity: socket+pid+start)")
    } else { log.line("could not identify server pid via lsof") }

    // Does --session default target the same socket? status is read-only.
    let sd = run(bin, ["--session", "default", "status", "--json"])
    let sdSock = (json(sd.stdout)?["server"] as? [String: Any])?["socket"] as? String
    log.line("--session default status --json -> status \(sd.status) socket=\(sdSock ?? "?") err=\(trunc(sd.err))")
    ep.sessionFlagMatches = (sdSock == ep.socket)
    log.line("sessions dir exists after --session default: \(FileManager.default.fileExists(atPath: home + "/.config/herdr/sessions"))")

    // Raw socket ping straight to the explicit endpoint.
    let (d, ms, e) = rawRequest(socketPath: ep.socket, #"{"id":"probe_ping","method":"ping","params":{}}"#)
    log.line("raw socket ping -> \(e ?? trunc(String(decoding: d ?? Data(), as: UTF8.self))) wall=\(fmt(ms))ms")
    return ep
}

struct AgentRef { var paneId: String; var name: String?; var kind: String; var status: String }

func parseAgents(_ d: Data) -> [AgentRef]? {
    guard let j = json(d), let r = j["result"] as? [String: Any], let list = r["agents"] as? [[String: Any]] else { return nil }
    return list.compactMap { a in
        guard let pane = a["pane_id"] as? String, pane.count < 64 else { return nil }
        return AgentRef(paneId: pane, name: a["name"] as? String, kind: a["agent"] as? String ?? "?",
                        status: a["agent_status"] as? String ?? "?")
    }
}

func readOnlyCommands(_ bin: String, _ ep: Endpoint) {
    log.line("== Read-only agent commands ==")
    let id = "local/\(ep.session)@\(ep.socket)#pid\(ep.serverPid.map(String.init) ?? "?")"
    let l = run(bin, ["agent", "list"])
    log.line("agent list -> status \(l.status) bytes=\(l.stdout.count) wall=\(fmt(l.wallMs))ms cpu=\(fmt(l.childCpuMs))ms err=\(trunc(l.err))")
    guard let agents = parseAgents(l.stdout), let first = agents.first else { log.line("no agents parsed"); return }
    for a in agents {
        log.line("  [\(id)] pane=\(a.paneId) name=\(a.name ?? "-") kind=\(a.kind) status=\(a.status)")
    }
    if ep.sessionFlagMatches {
    let sl = run(bin, ["--session", "default", "agent", "list"])
    log.line("--session default agent list -> status \(sl.status) count=\(parseAgents(sl.stdout)?.count ?? -1) err=\(trunc(sl.err))")
    } else { log.line("skipping --session default agent list: socket differs") }

    let g = run(bin, ["agent", "get", first.paneId])
    let gj = (json(g.stdout)?["result"] as? [String: Any])?["agent"] as? [String: Any]
    log.line("agent get \(first.paneId) [\(id)] -> status \(g.status) pane=\(gj?["pane_id"] ?? "?") status=\(gj?["agent_status"] ?? "?") wall=\(fmt(g.wallMs))ms err=\(trunc(g.err))")
    if gj == nil { log.line("  get raw keys: \(json(g.stdout)?.keys.sorted() ?? [])") }

    // visible source only: avoids history collection that may scroll the agent's viewport.
    let r = run(bin, ["agent", "read", first.paneId, "--source", "visible"])
    log.line("agent read \(first.paneId) --source visible [\(id)] -> status \(r.status) bytes=\(r.stdout.count) lines=\(r.out.split(separator: "\n").count) wall=\(fmt(r.wallMs))ms err=\(trunc(r.err)) (content not logged)")
    if let rj = json(r.stdout) { log.line("  read JSON keys: \((rj["result"] as? [String: Any])?.keys.sorted() ?? rj.keys.sorted())") }

    let bad = run(bin, ["agent", "get", "w999:p999"])
    log.line("agent get w999:p999 (nonexistent) -> status \(bad.status) err=\(trunc(bad.err))")
}

func stats(_ xs: [Double]) -> String {
    let s = xs.sorted()
    guard !s.isEmpty else { return "n=0" }
    let mean = s.reduce(0, +) / Double(s.count)
    return "n=\(s.count) mean=\(fmt(mean)) median=\(fmt(s[s.count / 2])) min=\(fmt(s.first!)) max=\(fmt(s.last!))"
}

func measure(_ label: String, _ ep: Endpoint, every: Double = 5, count: Int = 12, _ body: () -> (Double, Double, Int, Bool)) {
    log.line("== \(label): \(count) polls every \(Int(every))s ==")
    let srv0 = ep.serverPid.flatMap(serverCpuSeconds)
    let app0 = ProcessInfo.processInfo.systemUptime
    var selfRu0 = rusage(); getrusage(RUSAGE_SELF, &selfRu0)
    var walls: [Double] = [], cpus: [Double] = [], fails = 0, bytes = 0
    let start = Date()
    for i in 0..<count {
        let (w, c, b, ok) = body()
        walls.append(w); cpus.append(c); bytes = b
        if !ok { fails += 1 }
        let next = start.addingTimeInterval(Double(i + 1) * every)
        Thread.sleep(until: next)
    }
    var selfRu1 = rusage(); getrusage(RUSAGE_SELF, &selfRu1)
    func ms(_ t: timeval) -> Double { Double(t.tv_sec) * 1000 + Double(t.tv_usec) / 1000 }
    let selfCpu = ms(selfRu1.ru_utime) + ms(selfRu1.ru_stime) - ms(selfRu0.ru_utime) - ms(selfRu0.ru_stime)
    let srv1 = ep.serverPid.flatMap(serverCpuSeconds)
    log.line("wall ms: \(stats(walls))")
    log.line("child cpu ms: \(stats(cpus)) total=\(fmt(cpus.reduce(0, +)))")
    log.line("app self cpu ms over window: \(fmt(selfCpu)); elapsed s: \(fmt(ProcessInfo.processInfo.systemUptime - app0))")
    if let a = srv0, let b = srv1 { log.line("server cpu delta: \(fmt((b - a) * 1000))ms over window (includes all other clients)") }
    log.line("failures=\(fails) last payload bytes=\(bytes)")
}

func probe() {
    log.line("FocusPilot S4 Herdr probe starting; log=\(logPath)")
    logEnvironment()
    guard let bin = resolveBinary(), let ep = resolveEndpoint(bin) else { log.line("ABORT"); return }
    readOnlyCommands(bin, ep)
    measure("Baseline (no polling)", ep) { (0, 0, 0, true) }
    measure("CLI `agent list` polling", ep) {
        let r = run(bin, ["agent", "list"])
        return (r.wallMs, r.childCpuMs, r.stdout.count, r.status == 0 && parseAgents(r.stdout) != nil)
    }
    measure("Raw socket `agent.list` polling", ep) {
        let (d, w, e) = rawRequest(socketPath: ep.socket, #"{"id":"probe_list","method":"agent.list","params":{}}"#)
        return (w, 0, d?.count ?? 0, e == nil && d.flatMap(parseAgents) != nil)
    }
    log.line("DONE")
}


// MARK: - Focus mode

let scratchAgent = "s4-scratch"

struct FocusState { var workspace: String?; var tab: String?; var pane: String? }

func focusState(_ bin: String) -> FocusState {
    let r = run(bin, ["api", "snapshot"])
    let snap = (json(r.stdout)?["result"] as? [String: Any])?["snapshot"] as? [String: Any]
    return FocusState(workspace: snap?["focused_workspace_id"] as? String,
                      tab: snap?["focused_tab_id"] as? String,
                      pane: snap?["focused_pane_id"] as? String)
}

func describe(_ f: FocusState) -> String { "ws=\(f.workspace ?? "?") tab=\(f.tab ?? "?") pane=\(f.pane ?? "?")" }

func scratchInfo(_ bin: String) -> (status: String, pane: String, tab: String)? {
    let r = run(bin, ["agent", "get", scratchAgent])
    guard let a = (json(r.stdout)?["result"] as? [String: Any])?["agent"] as? [String: Any],
          let st = a["agent_status"] as? String, let pane = a["pane_id"] as? String, let tab = a["tab_id"] as? String
    else { log.line("agent get \(scratchAgent) failed: status \(r.status) err=\(trunc(r.err))"); return nil }
    return (st, pane, tab)
}

/// argv: focus tab|agent. The target is always derived from the scratch agent, never taken from argv.
func focusProbe() {
    let kind = CommandLine.arguments.dropFirst(2).first ?? ""
    log.line("FocusPilot S4 focus probe; kind=\(kind)")
    logEnvironment()
    guard kind == "tab" || kind == "agent", let bin = resolveBinary() else { log.line("ABORT: bad kind or no binary"); return }
    let owner = focusState(bin)
    log.line("BEFORE owner focus: \(describe(owner))")
    guard let ownerTab = owner.tab, let s0 = scratchInfo(bin) else { log.line("ABORT: missing owner focus or scratch agent"); return }
    log.line("BEFORE scratch \(scratchAgent): pane=\(s0.pane) tab=\(s0.tab) status=\(s0.status)")
    guard ownerTab != s0.tab else { log.line("ABORT: owner is already on the scratch tab"); return }

    let args = kind == "tab" ? ["tab", "focus", s0.tab] : ["agent", "focus", scratchAgent]
    let f = run(bin, args)
    log.line("FOCUS `herdr \(args.joined(separator: " "))` -> status \(f.status) wall=\(fmt(f.wallMs))ms out=\(trunc(f.out, 600)) err=\(trunc(f.err))")
    let after = focusState(bin)
    log.line("AFTER focus: \(describe(after)); scratch status=\(scratchInfo(bin)?.status ?? "?")")
    Thread.sleep(forTimeInterval: 3)  // long enough for the owner to see the TUI switch
    log.line("AFTER 3s hold: \(describe(focusState(bin))); scratch status=\(scratchInfo(bin)?.status ?? "?")")

    let r = run(bin, ["tab", "focus", ownerTab])
    log.line("RESTORE `herdr tab focus \(ownerTab)` -> status \(r.status) err=\(trunc(r.err))")
    let restored = focusState(bin)
    log.line("AFTER restore: \(describe(restored)); matches before: \(restored.pane == owner.pane && restored.tab == owner.tab && restored.workspace == owner.workspace)")
    log.line("AFTER restore scratch status=\(scratchInfo(bin)?.status ?? "?")")
    log.line("DONE")
}

// MARK: - Minimal GUI shell

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ n: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 80),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Herdr Probe (S4 spike)"
        let label = NSTextField(labelWithString: "Probing Herdr read-only… log: ~/Library/Logs/FocusPilotHerdrProbe")
        label.frame = NSRect(x: 16, y: 30, width: 400, height: 20)
        window.contentView?.addSubview(label)
        window.center()
        window.orderFrontRegardless()
        DispatchQueue.global().async {
            if focusMode { focusProbe() } else { probe() }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
