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

    private func importInbox(from inbox: TaskInbox? = nil) async throws -> Int {
        let repository = repository
        return try await (inbox ?? self.inbox).drain(isPermanent: TaskRepository.isPermanentAddFailure) {
            _ = try await repository.addFromHerdr($0)
        }.imported
    }

    private func titles() async throws -> [String] {
        try await repository.todayTasks().map(\.title)
    }

    private func appendRaw(_ text: String) throws {
        let handle = try FileHandle(forWritingTo: inbox.fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    @Test func queuedAddsAreImportedInOrder() async throws {
        try inbox.enqueue(herdrAdd("Reply to co-advisor"))
        try inbox.enqueue(herdrAdd("Re-run ablation by fri 23:59"))

        #expect(try await importInbox() == 2)
        #expect(try await titles() == ["Reply to co-advisor", "Re-run ablation"])
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
        await #expect(throws: DiskFull.self) { try await inbox.drain(isPermanent: { _ in false }) { _ in throw DiskFull() } }

        #expect(try await importInbox() == 1)
    }

    @Test func anUnreadableLineIsSkipped() async throws {
        try inbox.enqueue(herdrAdd("Reply to co-advisor"))
        try appendRaw("not json\n")
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

    // MARK: Failures that must not block the inbox

    @Test func aPermanentFailureIsSkippedAndTheRestImported() async throws {
        try inbox.enqueue(herdrAdd("First"))
        try inbox.enqueue(herdrAdd("Poison"))
        try inbox.enqueue(herdrAdd("Third"))
        struct Rejected: Error {}
        let repository = repository

        let drained = try await inbox.drain(isPermanent: { $0 is Rejected }) { request in
            if request.text == "Poison" { throw Rejected() }
            _ = try await repository.addFromHerdr(request)
        }

        #expect(drained == TaskInbox.Drained(imported: 2, skipped: 1))
        #expect(try await titles() == ["First", "Third"])
        #expect(try await importInbox() == 0)
    }

    @Test func aTemporaryFailureKeepsOnlyWhatWasNotImported() async throws {
        try inbox.enqueue(herdrAdd("First"))
        try inbox.enqueue(herdrAdd("Second"))
        struct Busy: Error {}
        let repository = repository
        await #expect(throws: Busy.self) {
            try await inbox.drain(isPermanent: { _ in false }) { request in
                if request.text == "Second" { throw Busy() }
                _ = try await repository.addFromHerdr(request)
            }
        }

        #expect(try await importInbox() == 1)
        #expect(try await titles() == ["First", "Second"])
    }

    @Test func aBlankTitleIsAPermanentFailure() {
        #expect(TaskRepository.isPermanentAddFailure(NewTask.Invalid.missingTitle))
        struct Busy: Error {}
        #expect(!TaskRepository.isPermanentAddFailure(Busy()))
    }

    @Test func eachDrainReadsAtMostTheLimit() async throws {
        let small = TaskInbox(directory: inbox.fileURL.deletingLastPathComponent(), readLimit: 700)
        for index in 1...5 { try small.enqueue(herdrAdd("Task \(index)")) }

        let first = try await importInbox(from: small)
        #expect(first >= 1 && first < 5)
        var total = first
        while total < 5 {
            let next = try await importInbox(from: small)
            #expect(next > 0)
            total += next
        }
        #expect(try await titles() == (1...5).map { "Task \($0)" })
    }

    @Test func aLineLongerThanTheLimitIsSkipped() async throws {
        let small = TaskInbox(directory: inbox.fileURL.deletingLastPathComponent(), readLimit: 700)
        try small.enqueue(herdrAdd(String(repeating: "x", count: 2000)))
        try small.enqueue(herdrAdd("After the long one"))

        var imported = 0
        for _ in 0..<5 { imported += try await importInbox(from: small) }

        #expect(try await titles() == ["After the long one"])
    }

    // MARK: Torn writes

    @Test func aLineTornByADyingCLIDoesNotSwallowTheNextAdd() async throws {
        try inbox.enqueue(herdrAdd("Before"))
        try appendRaw(#"{"id":"3F2A","text":"half writ"#)
        try inbox.enqueue(herdrAdd("After"))

        _ = try await importInbox()

        #expect(try await titles() == ["Before", "After"])
    }
}
