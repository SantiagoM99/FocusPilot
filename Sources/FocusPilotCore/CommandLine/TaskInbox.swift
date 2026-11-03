import Darwin
import Foundation
import os

/// Where `focuspilot add` queues tasks, and `focuspilot report` reports
/// (#67), while FocusPilot is not running. The app imports them when it
/// starts; request IDs make an import that is repeated or interrupted store
/// each one once. An add is a bare request line, as before reports existed;
/// a report line is `{"report": …}`.
///
/// One JSON request per line, appended and drained under an exclusive
/// `flock`, so concurrent CLI calls and the app never interleave. Each line
/// goes out in one `write`, after a newline if the file does not end in one,
/// so a CLI that dies mid-write can tear only its own line.
public struct TaskInbox: Sendable {
    public enum Refusal: Error, Equatable {
        case rateLimited
    }

    public struct Drained: Equatable, Sendable {
        public var imported: Int
        /// Lines dropped: unreadable, too long, or refused for good.
        public var skipped: Int
    }

    public let fileURL: URL
    /// The most one drain or rate check reads at once; a drain that stops at
    /// the limit leaves the rest for the next one.
    private let readLimit: Int

    private static let log = Logger(subsystem: "com.santiagom99.FocusPilot", category: "inbox")
    private static let newline = UInt8(ascii: "\n")

    public init(directory: URL, readLimit: Int = 1 << 20) {
        fileURL = directory.appending(path: "inbox.jsonl")
        self.readLimit = readLimit
    }

    /// Appends the report, unless its pane already queued
    /// `AddRateLimit.limit` reports in the last minute.
    public func enqueue(_ report: ReportRequest) throws {
        try append(try JSONEncoder().encode(ReportLine(report: report)), key: AddRateLimit.key(for: report.caller),
                   at: report.sentAt) { line in
            (try? JSONDecoder().decode(ReportLine.self, from: line)).map { (AddRateLimit.key(for: $0.report.caller), $0.report.sentAt) }
        }
    }

    /// Appends the request, unless its pane already queued
    /// `AddRateLimit.limit` adds in the last minute.
    public func enqueue(_ request: HerdrAddRequest) throws {
        try append(try JSONEncoder().encode(request), key: AddRateLimit.key(for: request.caller), at: request.capturedAt) { line in
            guard (try? JSONDecoder().decode(ReportLine.self, from: line)) == nil,
                  let queued = try? JSONDecoder().decode(HerdrAddRequest.self, from: line) else { return nil }
            return (AddRateLimit.key(for: queued.caller), queued.capturedAt)
        }
    }

    /// Appends one encoded line, unless `key` already has
    /// `AddRateLimit.limit` lines of the same kind (as `counted` reads them)
    /// in the minute before `instant`.
    private func append(_ encoded: Data, key: String, at instant: Date, counted: (Data) -> (String, Date)?) throws {
        let descriptor = try openLocked(appending: true)
        defer { close(descriptor) }
        let size = lseek(descriptor, 0, SEEK_END)
        // Only the newest adds matter for the limit, so read only the tail.
        let tailStart = max(0, Int(size) - readLimit)
        var tail = try read(descriptor, from: tailStart, count: Int(size) - tailStart)
        if tailStart > 0, let firstBreak = tail.firstIndex(of: Self.newline) { tail = tail[(firstBreak + 1)...] }

        var limit = AddRateLimit()
        for line in tail.split(separator: Self.newline) {
            guard let (queuedKey, queuedAt) = counted(Data(line)), queuedKey == key else { continue }
            _ = limit.allow(key, at: queuedAt)
        }
        guard limit.allow(key, at: instant) else { throw Refusal.rateLimited }

        var line = encoded + [Self.newline]
        if size > 0, tail.last != Self.newline { line.insert(Self.newline, at: 0) }
        let written = line.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        guard written == line.count else {
            // Leave no partial line behind for the next add to run into.
            ftruncate(descriptor, size)
            throw POSIXError(.EIO)
        }
    }

    /// Hands each queued add to `add` and each report to `reports`, in
    /// order, and removes the ones handled. A failure `isPermanent` judges
    /// permanent is logged and skipped; any other stops the drain and keeps
    /// that line and the rest for the next attempt. Without `reports`, the
    /// drain stops at the first report, leaving it and the rest queued.
    public func drain(isPermanent: (any Error) -> Bool, reports: (@Sendable (ReportRequest) async throws -> Void)? = nil,
                      _ add: @Sendable (HerdrAddRequest) async throws -> Void) async throws -> Drained {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return Drained(imported: 0, skipped: 0) }
        let descriptor = try openLocked(appending: false)
        defer { close(descriptor) }
        let size = Int(lseek(descriptor, 0, SEEK_END))
        let data = try read(descriptor, from: 0, count: min(size, readLimit))
        var drained = Drained(imported: 0, skipped: 0)
        var handled = 0

        defer { try? removePrefix(handled, of: descriptor) }
        var start = data.startIndex
        while start < data.endIndex {
            guard let end = data[start...].firstIndex(of: Self.newline) else {
                if data.count == size {
                    // A torn last line: its writer died, since we hold the lock.
                    Self.log.error("Dropped a torn inbox line of \(data.endIndex - start) bytes")
                    drained.skipped += 1
                    handled = size
                } else if start == data.startIndex {
                    // One line longer than the limit: skip to its end.
                    handled = try endOfLine(in: descriptor, after: data.count) ?? size
                    Self.log.error("Dropped an inbox line longer than \(readLimit) bytes")
                    drained.skipped += 1
                }
                break
            }
            let line = data[start..<end]
            if let queued = try? JSONDecoder().decode(ReportLine.self, from: Data(line)) {
                guard let reports else { break }
                start = end + 1
                do {
                    try await reports(queued.report)
                    drained.imported += 1
                } catch where isPermanent(error) {
                    Self.log.error("Dropped queued report \(queued.report.id, privacy: .public): \(String(describing: error), privacy: .public)")
                    drained.skipped += 1
                }
                handled = start
                continue
            }
            start = end + 1
            guard let request = try? JSONDecoder().decode(HerdrAddRequest.self, from: Data(line)) else {
                Self.log.error("Dropped an unreadable inbox line")
                drained.skipped += 1
                handled = start
                continue
            }
            do {
                try await add(request)
                drained.imported += 1
            } catch where isPermanent(error) {
                Self.log.error("Dropped inbox request \(request.id, privacy: .public): \(String(describing: error), privacy: .public)")
                drained.skipped += 1
            }
            handled = start
        }
        return drained
    }

    // MARK: File

    /// Opens (creating) the inbox, owner-only, holding an exclusive lock
    /// until the descriptor is closed. `appending` opens with O_APPEND, so
    /// every write lands at the end; the drain does not, because it rewrites
    /// the file in place with `pwrite`, which O_APPEND would redirect.
    private func openLocked(appending: Bool) throws -> Int32 {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let descriptor = open(fileURL.path, O_RDWR | O_CREAT | O_CLOEXEC | (appending ? O_APPEND : 0), 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            close(descriptor)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return descriptor
    }

    private func read(_ descriptor: Int32, from offset: Int, count: Int) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: count)
        var filled = 0
        while filled < count {
            let got = buffer[filled...].withUnsafeMutableBytes { pread(descriptor, $0.baseAddress, $0.count, off_t(offset + filled)) }
            guard got > 0 else {
                if got < 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                break
            }
            filled += got
        }
        return Data(buffer[..<filled])
    }

    /// The offset just past the first newline at or after `offset`.
    private func endOfLine(in descriptor: Int32, after offset: Int) throws -> Int? {
        var position = offset
        while true {
            let chunk = try read(descriptor, from: position, count: 64 * 1024)
            guard !chunk.isEmpty else { return nil }
            if let index = chunk.firstIndex(of: Self.newline) { return position + index + 1 }
            position += chunk.count
        }
    }

    /// Moves everything after the first `count` bytes to the front, in
    /// place: the file is never replaced, so a CLI waiting on the lock still
    /// appends to the same file.
    private func removePrefix(_ count: Int, of descriptor: Int32) throws {
        guard count > 0 else { return }
        let size = Int(lseek(descriptor, 0, SEEK_END))
        var source = count
        var destination = 0
        while source < size {
            let chunk = try read(descriptor, from: source, count: min(64 * 1024, size - source))
            let written = chunk.withUnsafeBytes { pwrite(descriptor, $0.baseAddress, $0.count, off_t(destination)) }
            guard written == chunk.count else { throw POSIXError(.EIO) }
            source += chunk.count
            destination += chunk.count
        }
        ftruncate(descriptor, off_t(destination))
    }
}

/// A queued report, tagged so it is never read as an add.
struct ReportLine: Codable, Equatable {
    var report: ReportRequest
}
