// S5 folder-access probe. Throwaway spike code; never merged.
// One source, built into several app bundles (unsandboxed, sandboxed, sandboxed without the
// app-scope bookmark entitlement). Run the bundle's executable directly with a command for
// headless tests; launch the bundle with no command (`open -a`) to receive folders through
// application(_:open:); use `pick` for the human NSOpenPanel step. Every command prints one
// JSON object per line on stdout.
import AppKit
import Darwin
import Foundation

// MARK: Output

func emit(_ dict: [String: Any]) {
    var d = dict
    d["variant"] = Bundle.main.bundleIdentifier ?? "?"
    d["sandboxed"] = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    d["at"] = ISO8601DateFormatter().string(from: Date())
    let data = try! JSONSerialization.data(withJSONObject: d, options: [.sortedKeys])
    FileHandle.standardOutput.write(data + Data("\n".utf8))
}

func errInfo(_ error: Error) -> [String: Any] {
    let ns = error as NSError
    return ["domain": ns.domain, "code": ns.code, "message": ns.localizedDescription]
}

func ms(_ start: UInt64) -> Double { Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - start) / 1e6 }
func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }

// MARK: Store (inside the sandbox container when sandboxed)

struct Entry: Codable {
    var bookmark: Data
    var options: String          // "security-scope" or "plain"
    var pathAtCreation: String
    var fileID: UInt64?          // st_ino; with the volume UUID, detects same-path substitution
    var volumeUUID: String?
    var createdAt: Date
    var refreshedAt: Date?
}

let storeURL: URL = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("FocusPilotSpikeS5/\(Bundle.main.bundleIdentifier ?? "probe")", isDirectory: true)
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base.appendingPathComponent("store.json")
}()

func loadStore() -> [String: Entry] {
    guard let data = try? Data(contentsOf: storeURL) else { return [:] }
    let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
    return (try? dec.decode([String: Entry].self, from: data)) ?? [:]
}

func saveStore(_ s: [String: Entry]) {
    let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    try! enc.encode(s).write(to: storeURL, options: .atomic)
}

// MARK: Identity

func identity(_ url: URL) -> (UInt64?, String?) {
    var st = stat()
    let ino: UInt64? = stat(url.path, &st) == 0 ? UInt64(st.st_ino) : nil
    let vol = (try? url.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString
    return (ino, vol)
}

// MARK: Bookmarks

var useScope: Bool { ProcessInfo.processInfo.environment["S5_PLAIN"] == nil }

func makeBookmark(_ url: URL) throws -> Data {
    try url.bookmarkData(options: useScope ? [.withSecurityScope] : [],
                         includingResourceValuesForKeys: nil, relativeTo: nil)
}

func createEntry(name: String, url: URL) -> [String: Any] {
    let t = now()
    do {
        let data = try makeBookmark(url)
        let elapsed = ms(t)
        let (ino, vol) = identity(url)
        var s = loadStore()
        s[name] = Entry(bookmark: data, options: useScope ? "security-scope" : "plain",
                        pathAtCreation: url.path, fileID: ino, volumeUUID: vol, createdAt: Date())
        saveStore(s)
        return ["cmd": "create", "name": name, "ok": true, "path": url.path, "bytes": data.count,
                "ms": elapsed, "options": useScope ? "security-scope" : "plain"]
    } catch {
        return ["cmd": "create", "name": name, "ok": false, "path": url.path, "error": errInfo(error), "ms": ms(t)]
    }
}

/// Lists a directory and reports whether reading succeeded; this is the real access test.
func probeRead(_ url: URL) -> [String: Any] {
    do {
        let items = try FileManager.default.contentsOfDirectory(atPath: url.path)
        return ["readable": true, "entries": items.count]
    } catch {
        return ["readable": false, "readError": errInfo(error)]
    }
}

func probeWrite(_ url: URL) -> [String: Any] {
    let f = url.appendingPathComponent(".s5-write-probe-\(getpid())")
    do {
        try Data("x".utf8).write(to: f)
        try FileManager.default.removeItem(at: f)
        return ["writable": true]
    } catch {
        return ["writable": false, "writeError": errInfo(error)]
    }
}

func trashURL() -> URL? { try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false) }

/// Resolves a stored entry. Options: access (start/stop scope), refresh (rewrite stale bookmark),
/// subpath (read a path below the resolved folder while access is held), root (containment check).
func resolveEntry(name: String, access: Bool, refresh: Bool, subpath: String?, root: String?) -> [String: Any] {
    var s = loadStore()
    guard var e = s[name] else { return ["cmd": "resolve", "name": name, "ok": false, "error": "no such entry"] }
    var out: [String: Any] = ["cmd": "resolve", "name": name, "pathAtCreation": e.pathAtCreation, "options": e.options]
    var stale = false
    let t = now()
    let url: URL
    do {
        url = try URL(resolvingBookmarkData: e.bookmark,
                      options: e.options == "security-scope" ? [.withSecurityScope, .withoutUI, .withoutMounting] : [.withoutUI, .withoutMounting],
                      relativeTo: nil, bookmarkDataIsStale: &stale)
    } catch {
        out["ok"] = false; out["error"] = errInfo(error); out["resolveMs"] = ms(t)
        return out
    }
    out["resolveMs"] = ms(t)
    out["ok"] = true
    out["path"] = url.path
    out["isStale"] = stale
    out["moved"] = url.path != e.pathAtCreation
    out["exists"] = FileManager.default.fileExists(atPath: url.path)
    let (ino, vol) = identity(url)
    out["sameIdentity"] = (ino == e.fileID && vol == e.volumeUUID)
    out["fileID"] = ino.map { NSNumber(value: $0) } ?? NSNull()
    out["storedFileID"] = e.fileID.map { NSNumber(value: $0) } ?? NSNull()
    if let trash = trashURL() { out["inTrash"] = Containment.check(root: trash.path, candidate: url.path).inside }
    if let root { out["containment"] = Containment.check(root: root, candidate: url.path).json }

    var started = false
    if access {
        let t2 = now()
        started = url.startAccessingSecurityScopedResource()
        out["startAccessing"] = started
        out["startMs"] = ms(t2)
    }
    out.merge(probeRead(url)) { a, _ in a }
    out.merge(probeWrite(url)) { a, _ in a }
    if let subpath {
        let sub = url.appendingPathComponent(subpath)
        var r = probeRead(sub)
        r["subpath"] = subpath
        r["realpath"] = Containment.realpath(sub.path) ?? NSNull()
        r["containment"] = Containment.check(root: url.path, candidate: sub.path).json
        out["sub"] = r
    }
    if stale && refresh {
        do {
            e.bookmark = try makeBookmark(url)
            e.pathAtCreation = url.path
            e.refreshedAt = Date()
            s[name] = e
            saveStore(s)
            out["refreshed"] = true
        } catch {
            out["refreshed"] = false; out["refreshError"] = errInfo(error)
        }
    }
    if started { url.stopAccessingSecurityScopedResource() }
    return out
}

// MARK: Containment (candidate design for provisioning: canonicalize, then compare components)

enum Containment {
    struct Result {
        var inside: Bool
        var reason: String
        var canonRoot: String?
        var canonCandidate: String?
        var json: [String: Any] {
            ["inside": inside, "reason": reason, "canonRoot": canonRoot ?? NSNull(), "canonCandidate": canonCandidate ?? NSNull()]
        }
    }

    static func realpath(_ p: String) -> String? {
        guard let r = Darwin.realpath(p, nil) else { return nil }
        defer { free(r) }
        return String(cString: r)
    }

    /// For a path that may not exist yet: realpath of the deepest existing ancestor, then the
    /// remaining components appended after rejecting "." and "..".
    static func canonicalize(_ p: String) -> (String?, String) {
        let comps = (p as NSString).pathComponents
        var i = comps.count
        while i > 0 {
            let prefix = NSString.path(withComponents: Array(comps[0..<i]))
            if let r = realpath(prefix) {
                let rest = Array(comps[i...])
                // realpath fails on a dangling symlink too; it must not pass as a missing name.
                var st = stat()
                if let first = rest.first, lstat(NSString.path(withComponents: [r, first]), &st) == 0 {
                    return (nil, "dangling-symlink-or-unreadable")
                }
                if rest.contains(where: { $0 == ".." || $0 == "." }) { return (nil, "dot-component-in-missing-tail") }
                return (rest.isEmpty ? r : NSString.path(withComponents: [r] + rest), i == comps.count ? "exists" : "partial")
            }
            i -= 1
        }
        return (nil, "no-existing-ancestor")
    }

    static func caseSensitive(_ p: String) -> Bool {
        (try? URL(fileURLWithPath: p).resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))?.volumeSupportsCaseSensitiveNames ?? true
    }

    static func fold(_ s: String, caseSensitive: Bool) -> String {
        // APFS keeps names as given but compares them normalization-insensitively.
        let n = s.precomposedStringWithCanonicalMapping
        return caseSensitive ? n : n.lowercased()
    }

    static func check(root: String, candidate: String) -> Result {
        guard let r = realpath(root) else { return Result(inside: false, reason: "root-missing", canonRoot: nil, canonCandidate: nil) }
        let (c, how) = canonicalize(candidate)
        guard let c else { return Result(inside: false, reason: how, canonRoot: r, canonCandidate: nil) }
        let cs = caseSensitive(r)
        let rc = (r as NSString).pathComponents.map { fold($0, caseSensitive: cs) }
        let cc = (c as NSString).pathComponents.map { fold($0, caseSensitive: cs) }
        let inside = cc.count >= rc.count && Array(cc[0..<rc.count]) == rc
        return Result(inside: inside, reason: inside ? "inside(\(how))" : "outside(\(how))", canonRoot: r, canonCandidate: c)
    }
}

/// Creates one child directory under a root without following symlinks: the name must be a single
/// component, mkdirat never follows a final symlink, and openat(O_NOFOLLOW) confirms the result.
func safeMkdir(root: URL, name: String) -> [String: Any] {
    var out: [String: Any] = ["cmd": "mkchild", "root": root.path, "name": name]
    if name.isEmpty || name == "." || name == ".." || name.contains("/") || name.contains("\0") {
        out["ok"] = false; out["error"] = "invalid-name"; return out
    }
    let rfd = open(root.path, O_RDONLY | O_DIRECTORY)
    guard rfd >= 0 else { out["ok"] = false; out["error"] = "open-root errno \(errno)"; return out }
    defer { close(rfd) }
    if mkdirat(rfd, name, 0o755) != 0 {
        let e = errno
        var st = stat()
        let isLink = fstatat(rfd, name, &st, AT_SYMLINK_NOFOLLOW) == 0 && (st.st_mode & S_IFMT) == S_IFLNK
        out["ok"] = false; out["error"] = e == EEXIST ? (isLink ? "exists-as-symlink" : "exists") : "mkdirat errno \(e)"
        return out
    }
    let cfd = openat(rfd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    out["ok"] = cfd >= 0
    if cfd >= 0 { close(cfd) }
    return out
}

// MARK: Bench

func bench(path: String, n: Int) -> [String: Any] {
    let url = URL(fileURLWithPath: path)
    func stats(_ xs: [Double]) -> [String: Double] {
        let s = xs.sorted()
        return ["median": s[s.count / 2], "p95": s[Int(Double(s.count) * 0.95)], "max": s.last!, "min": s.first!]
    }
    var create: [Double] = [], resolve: [Double] = [], start: [Double] = [], contain: [Double] = []
    var data = Data()
    for _ in 0..<n {
        let t = now(); data = (try? makeBookmark(url)) ?? Data(); create.append(ms(t))
    }
    for _ in 0..<n {
        var stale = false
        let t = now()
        let u = try? URL(resolvingBookmarkData: data, options: useScope ? [.withSecurityScope, .withoutUI] : [.withoutUI],
                         relativeTo: nil, bookmarkDataIsStale: &stale)
        resolve.append(ms(t))
        let t2 = now()
        let ok = u?.startAccessingSecurityScopedResource() ?? false
        start.append(ms(t2))
        if ok { u?.stopAccessingSecurityScopedResource() }
    }
    for _ in 0..<n {
        let t = now(); _ = Containment.check(root: path, candidate: path + "/child/../child2"); contain.append(ms(t))
    }
    return ["cmd": "bench", "path": path, "n": n, "bytes": data.count, "createMs": stats(create), "resolveMs": stats(resolve),
            "startAccessingMs": stats(start), "containmentMs": stats(contain)]
}

// MARK: Commands

final class Delegate: NSObject, NSApplicationDelegate {
    var received = false
    func application(_ application: NSApplication, open urls: [URL]) {
        received = true
        for u in urls {
            var r = createEntry(name: "opened-" + u.lastPathComponent, url: u)
            r["via"] = "application(_:open:)"
            r.merge(probeRead(u)) { a, _ in a }
            appendLog(r)
        }
        NSApp.terminate(nil)
    }
    func applicationDidFinishLaunching(_ n: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if !self.received { appendLog(["cmd": "open", "received": false]) ; NSApp.terminate(nil) }
        }
    }
}

/// Launches through LaunchServices have no terminal, so they log to the store directory.
func appendLog(_ dict: [String: Any]) {
    var d = dict
    d["at"] = ISO8601DateFormatter().string(from: Date())
    let url = storeURL.deletingLastPathComponent().appendingPathComponent("open-log.jsonl")
    let line = (try! JSONSerialization.data(withJSONObject: d, options: [.sortedKeys])) + Data("\n".utf8)
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line); h.closeFile() } else { try? line.write(to: url) }
}

func pick(name: String, start: String?) {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.activate()
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.message = "S5 spike: choose the folder named in SPIKE_NOTES.md for entry \"\(name)\""
    if let start { panel.directoryURL = URL(fileURLWithPath: start) }
    let t = now()
    let resp = panel.runModal()
    let waited = ms(t)
    guard resp == .OK, let url = panel.url else { emit(["cmd": "pick", "ok": false, "cancelled": true]); return }
    var r = createEntry(name: name, url: url)
    r["via"] = "NSOpenPanel"; r["panelMs"] = waited
    r.merge(probeRead(url)) { a, _ in a }
    emit(r)
}

let args = Array(CommandLine.arguments.dropFirst())
func opt(_ k: String) -> String? { args.firstIndex(of: k).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
func flag(_ k: String) -> Bool { args.contains(k) }

switch args.first {
case nil:
    let d = Delegate()
    NSApplication.shared.delegate = d
    NSApplication.shared.run()
case "whoami":
    emit(["cmd": "whoami", "home": NSHomeDirectory(), "store": storeURL.path, "pid": getpid()])
case "create":
    emit(createEntry(name: args[1], url: URL(fileURLWithPath: args[2])))
case "resolve":
    emit(resolveEntry(name: args[1], access: flag("--access"), refresh: flag("--refresh"), subpath: opt("--sub"), root: opt("--root")))
case "read":                      // direct access without any bookmark
    var r = probeRead(URL(fileURLWithPath: args[1])); r["cmd"] = "read"; r["path"] = args[1]; emit(r)
case "export":
    emit(["cmd": "export", "name": args[1], "b64": loadStore()[args[1]]?.bookmark.base64EncodedString() ?? ""])
case "import":                    // bookmark data produced by another app
    let s0 = loadStore()
    var s = s0
    let data = Data(base64Encoded: args[2])!
    s[args[1]] = Entry(bookmark: data, options: args.count > 3 ? args[3] : "security-scope", pathAtCreation: "?", fileID: nil, volumeUUID: nil, createdAt: Date())
    saveStore(s)
    emit(["cmd": "import", "name": args[1], "bytes": data.count])
case "mkchild":                   // resolve root entry, hold access, create child safely, bookmark it
    let s = loadStore()
    guard let e = s[args[1]] else { emit(["cmd": "mkchild", "ok": false, "error": "no entry"]); exit(1) }
    var stale = false
    let root = try! URL(resolvingBookmarkData: e.bookmark, options: e.options == "security-scope" ? [.withSecurityScope] : [], relativeTo: nil, bookmarkDataIsStale: &stale)
    let started = root.startAccessingSecurityScopedResource()
    var r = safeMkdir(root: root, name: args[2])
    r["startAccessing"] = started
    emit(r)
    if r["ok"] as? Bool == true, let childName = opt("--bookmark-as") {
        emit(createEntry(name: childName, url: root.appendingPathComponent(args[2])))
    }
    if started { root.stopAccessingSecurityScopedResource() }
case "contain":
    var r = Containment.check(root: args[1], candidate: args[2]).json
    r["cmd"] = "contain"; r["root"] = args[1]; r["candidate"] = args[2]
    r["foundationResolving"] = URL(fileURLWithPath: args[2]).resolvingSymlinksInPath().path
    r["foundationStandardized"] = URL(fileURLWithPath: args[2]).standardizedFileURL.path
    emit(r)
case "bench":
    emit(bench(path: args[1], n: Int(args[2]) ?? 200))
case "bench-entry":               // bench using an already-granted entry (sandbox)
    let e = loadStore()[args[1]]!
    var stale = false
    let u = try! URL(resolvingBookmarkData: e.bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
    let ok = u.startAccessingSecurityScopedResource()
    var r = bench(path: u.path, n: Int(args[2]) ?? 200)
    r["entry"] = args[1]; r["heldAccess"] = ok
    emit(r)
    if ok { u.stopAccessingSecurityScopedResource() }
case "pick":
    pick(name: args[1], start: opt("--start"))
case "report":
    let s = loadStore()
    emit(["cmd": "report", "store": storeURL.path, "entries": s.mapValues { ["path": $0.pathAtCreation, "options": $0.options, "bytes": $0.bookmark.count] },
          "openLog": (try? String(contentsOf: storeURL.deletingLastPathComponent().appendingPathComponent("open-log.jsonl"), encoding: .utf8)) ?? ""])
case "trash":
    var r: [String: Any] = ["cmd": "trash", "path": args[1]]
    do {
        var res: NSURL?
        try FileManager.default.trashItem(at: URL(fileURLWithPath: args[1]), resultingItemURL: &res)
        r["ok"] = true; r["trashedTo"] = res?.path ?? NSNull()
    } catch { r["ok"] = false; r["error"] = errInfo(error) }
    emit(r)
case "forget":
    var s = loadStore(); s[args[1]] = nil; saveStore(s); emit(["cmd": "forget", "name": args[1]])
default:
    FileHandle.standardError.write(Data("unknown command\n".utf8)); exit(2)
}
