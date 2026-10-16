import Foundation
import Testing
@testable import FocusPilotCore

@Suite("Add rate limit")
struct AddRateLimitTests {
    private let start = wednesdayMorningInBogota

    @Test func allowsTwentyAddsPerMinutePerPane() {
        var limit = AddRateLimit()
        let allowed = (0..<21).map { limit.allow("w4:p2", at: start.addingTimeInterval(Double($0))) }
        #expect(allowed == Array(repeating: true, count: 20) + [false])
    }

    @Test func eachPaneHasItsOwnBudget() {
        var limit = AddRateLimit()
        for second in 0..<20 { _ = limit.allow("w4:p2", at: start.addingTimeInterval(Double(second))) }
        let otherPane = limit.allow("w5:p1", at: start.addingTimeInterval(20))
        #expect(otherPane)
    }

    @Test func theBudgetComesBackAMinuteLater() {
        var limit = AddRateLimit()
        for _ in 0..<20 { _ = limit.allow("w4:p2", at: start) }
        let withinTheMinute = limit.allow("w4:p2", at: start.addingTimeInterval(59))
        #expect(!withinTheMinute)
        let aMinuteLater = limit.allow("w4:p2", at: start.addingTimeInterval(60))
        #expect(aMinuteLater)
    }

    @Test func refusedAddsDoNotExtendTheWait() {
        var limit = AddRateLimit()
        for _ in 0..<20 { _ = limit.allow("w4:p2", at: start) }
        for second in 1..<60 { _ = limit.allow("w4:p2", at: start.addingTimeInterval(Double(second))) }
        let aMinuteLater = limit.allow("w4:p2", at: start.addingTimeInterval(60))
        #expect(aMinuteLater)
    }
}

@Suite("Command service")
struct CommandServiceTests {
    private let repository: TaskRepository
    private let service: CommandService

    init() throws {
        repository = try TaskRepository(location: StorageLocation(directory: makeTemporaryDirectory()),
                                        now: { wednesdayMorningInBogota })
        service = CommandService(repository: repository, now: { wednesdayMorningInBogota })
    }

    @Test func addIsStoredAndReported() async throws {
        let response = await service.handle(.add(herdrAdd("Reply to co-advisor")))

        guard case .added(let result) = response else {
            Issue.record("expected an add, got \(response)")
            return
        }
        #expect(result.title == "Reply to co-advisor")
        #expect(try await repository.tasks().count == 1)
    }

    @Test func aBurstFromOnePaneIsRefusedWithAMessage() async throws {
        for index in 0..<20 { _ = await service.handle(.add(herdrAdd("Task \(index)"))) }

        let response = await service.handle(.add(herdrAdd("One too many")))

        #expect(response == .refused(CommandService.rateLimitMessage))
        #expect(try await repository.tasks().count == 20)
    }

    @Test func addsOutsideHerdrShareOneBudget() async throws {
        for index in 0..<20 { _ = await service.handle(.add(herdrAdd("Task \(index)", from: nil))) }
        #expect(await service.handle(.add(herdrAdd("One too many", from: nil))) == .refused(CommandService.rateLimitMessage))
    }

    @Test func tasksReturnsTheScope() async throws {
        _ = await service.handle(.add(herdrAdd("Reply to co-advisor", from: nil)))
        #expect(await service.handle(.tasks(nil)) == .tasks(HerdrTaskScope(now: nil, projectTitle: nil, tasks: [])))
    }

    @Test func aBlankAddIsRefused() async throws {
        #expect(await service.handle(.add(herdrAdd("   "))) == .refused("Nothing to add: the task needs a title."))
    }
}
