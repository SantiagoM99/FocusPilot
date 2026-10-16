import Foundation
import Testing
@testable import FocusPilotCore

@Suite("Task inbox")
struct TaskInboxTests {
    private let directory: URL
    private let inbox: TaskInbox
    private let repository: TaskRepository

    init() throws {
        directory = try makeTemporaryDirectory()
        inbox = TaskInbox(directory: directory.appending(path: "CommandLine"))
        repository = try TaskRepository(location: StorageLocation(directory: directory), now: { wednesdayMorningInBogota })
    }

    private func importInbox() async throws -> Int {
        try await inbox.drain { try await repository.addFromHerdr($0) }
    }

    @Test func queuedAddsAreImportedInOrder() async throws {
        try inbox.enqueue(herdrAdd("Reply to co-advisor"))
        try inbox.enqueue(herdrAdd("Re-run ablation by fri 23:59"))

        #expect(try await importInbox() == 2)
        #expect(try await repository.todayTasks().map(\.title) == ["Reply to co-advisor", "Re-run ablation"])
        #expect(try await repository.todayTasks().allSatisfy(\.isFromHerdr))
    }

    @Test func importingEmptiesTheInbox() async throws {
        try inbox.enqueue(herdrAdd("Reply to co-advisor"))
        _ = try await importInbox()

        #expect(try await importInbox() == 0)
        #expect(try await repository.tasks().count == 1)
    }

    @Test func anAddAlreadyStoredIsNotDuplicated() async throws {
        // The CLI queues a request whose reply was lost, though the app had saved it.
        let request = herdrAdd("Reply to co-advisor")
        _ = try await repository.addFromHerdr(request)
        try inbox.enqueue(request)

        _ = try await importInbox()

        #expect(try await repository.tasks().count == 1)
    }

    @Test func aFailedImportKeepsTheInboxForTheNextTry() async throws {
        try inbox.enqueue(herdrAdd("Reply to co-advisor"))
        struct DiskFull: Error {}
        await #expect(throws: DiskFull.self) { try await inbox.drain { _ in throw DiskFull() } }

        #expect(try await importInbox() == 1)
    }

    @Test func anUnreadableLineIsSkipped() async throws {
        try inbox.enqueue(herdrAdd("Reply to co-advisor"))
        let handle = try FileHandle(forWritingTo: inbox.fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("not json\n".utf8))
        try handle.close()
        try inbox.enqueue(herdrAdd("Re-run ablation"))

        #expect(try await importInbox() == 2)
    }

    @Test func aBurstFromOnePaneIsRefusedWhileQueued() throws {
        for index in 0..<20 { try inbox.enqueue(herdrAdd("Task \(index)")) }
        #expect(throws: TaskInbox.Refusal.rateLimited) { try inbox.enqueue(herdrAdd("One too many")) }
        let otherPane = HerdrCaller(server: herdrServer, workspaceID: "w5", paneID: "w5:p1")
        try inbox.enqueue(herdrAdd("Other pane", from: otherPane))
    }

    @Test func theInboxIsReadableOnlyByTheOwner() throws {
        try inbox.enqueue(herdrAdd("Reply to co-advisor"))
        let file = try FileManager.default.attributesOfItem(atPath: inbox.fileURL.path)[.posixPermissions] as? Int
        let folder = try FileManager.default.attributesOfItem(atPath: inbox.fileURL.deletingLastPathComponent().path)[.posixPermissions] as? Int
        #expect(file == 0o600)
        #expect(folder == 0o700)
    }
}
