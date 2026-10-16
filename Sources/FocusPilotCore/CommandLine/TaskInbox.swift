import Darwin
import Foundation

/// Where `focuspilot add` queues tasks while FocusPilot is not running. The
/// app imports them through `TaskRepository` when it starts; request IDs
/// make an import that is repeated or interrupted store each task once.
///
/// One JSON request per line, appended and drained under an exclusive
/// `flock`, so concurrent CLI calls and the app never interleave.
public struct TaskInbox: Sendable {
    public enum Refusal: Error, Equatable {
        case rateLimited
    }

    public let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appending(path: "inbox.jsonl")
    }

    /// Appends the request, unless its pane already queued
    /// `AddRateLimit.limit` adds in the last minute.
    public func enqueue(_ request: HerdrAddRequest) throws {
        try withLockedFile { handle in
            var limit = AddRateLimit()
            let key = AddRateLimit.key(for: request.caller)
            for queued in Self.requests(in: try handle.readToEnd() ?? Data())
            where AddRateLimit.key(for: queued.caller) == key {
                _ = limit.allow(key, at: queued.capturedAt)
            }
            guard limit.allow(key, at: request.capturedAt) else { throw Refusal.rateLimited }
            try handle.seekToEnd()
            try handle.write(contentsOf: try JSONEncoder().encode(request) + Data("\n".utf8))
        }
    }

    /// Hands each queued request to `add` in order, then empties the inbox.
    /// If an add throws, the inbox is kept whole for the next attempt.
    /// Returns how many requests were handed over.
    public func drain(_ add: (HerdrAddRequest) async throws -> Void) async throws -> Int {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return 0 }
        return try await withLockedFile { handle in
            let requests = Self.requests(in: try handle.readToEnd() ?? Data())
            for request in requests { try await add(request) }
            try handle.truncate(atOffset: 0)
            return requests.count
        }
    }

    /// Lines that do not decode are skipped rather than blocking the rest.
    private static func requests(in data: Data) -> [HerdrAddRequest] {
        data.split(separator: UInt8(ascii: "\n")).compactMap { try? JSONDecoder().decode(HerdrAddRequest.self, from: Data($0)) }
    }

    private func withLockedFile<T>(_ body: (FileHandle) async throws -> T) async throws -> T {
        let handle = try openLocked()
        defer { try? handle.close() }
        return try await body(handle)
    }

    private func withLockedFile<T>(_ body: (FileHandle) throws -> T) throws -> T {
        let handle = try openLocked()
        defer { try? handle.close() }
        return try body(handle)
    }

    /// Opens (creating) the inbox, owner-only, holding an exclusive lock
    /// until the handle is closed.
    private func openLocked() throws -> FileHandle {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let descriptor = open(fileURL.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        guard flock(descriptor, LOCK_EX) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return handle
    }
}
