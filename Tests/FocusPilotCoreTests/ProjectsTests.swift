import Foundation
import Testing
@testable import FocusPilotCore

@Suite("Projects")
struct ProjectsTests {
    private let repository: TaskRepository

    init() throws {
        repository = try TaskRepository(location: StorageLocation(directory: makeTemporaryDirectory()),
                                        now: { wednesdayMorningInBogota })
    }

    private func deadline(_ text: String) -> Deadline {
        DeadlineParser(now: wednesdayMorningInBogota, timeZone: bogota).parse(text)!
    }

    @discardableResult
    private func add(_ title: String, _ project: String?, _ due: String? = nil) async throws -> Int64 {
        try await repository.addTask(NewTask(title: title, projectName: project, deadline: due.map(deadline))).id!
    }

    @Test func projectsAreListedAlphabeticallyWithOpenTaskCountsAndTheNearestDeadline() async throws {
        try await add("Explain baseline", "NLP report", "Oct 20")
        try await add("Reply to co-advisor", "NLP report", "fri 23:59")
        try await add("PhD shortlist", "Applications", "Oct 20")
        try await add("Renew library access", nil)

        let projects = try await repository.projects()

        #expect(projects.map(\.title) == ["Applications", "NLP report", "No project"])
        #expect(projects.map(\.openTaskCount) == [1, 2, 1])
        #expect(projects[1].nearestDeadline == deadline("fri 23:59"))
        #expect(projects[2].id == nil)
        #expect(projects[2].nearestDeadline == nil)
    }

    @Test func dateOnlyDeadlineCountsUntilTheEndOfItsDay() async throws {
        try await add("Timed", "Thesis", "Oct 16 22:00")
        try await add("Date only", "Thesis", "Oct 16")

        #expect(try await repository.projects().first?.nearestDeadline == deadline("Oct 16 22:00"))
        #expect(deadline("Oct 16").endInstant == instant("2026-10-17T00:00:00-05:00"))
    }

    @Test func projectTasksUseTheSameManualOrderAsToday() async throws {
        let first = try await add("Explain baseline", "NLP report")
        try await add("PhD shortlist", "Applications")
        let third = try await add("Reply to co-advisor", "NLP report")
        try await repository.moveTask(third, to: .next, .before(first))
        try await repository.moveTask(first, to: .now, .top)

        let projectID = try #require(try await repository.projects().first { $0.title == "NLP report" }?.id)
        let tasks = try await repository.projectTasks(projectID)

        #expect(tasks.map(\.title) == ["Explain baseline", "Reply to co-advisor"])
        #expect(tasks.map(\.status) == [.now, .next])
    }

    @Test func tasksWithoutAProjectAreListedTogether() async throws {
        try await add("Renew library access", nil)
        try await add("PhD shortlist", "Applications")

        #expect(try await repository.projectTasks(nil).map(\.title) == ["Renew library access"])
    }
}

@Suite("ProjectSummary text")
struct ProjectSummaryTextTests {
    private let now = wednesdayMorningInBogota

    private func summary(_ count: Int, _ due: String?) -> ProjectSummary {
        let deadline = due.map { DeadlineParser(now: now, timeZone: bogota).parse($0)! }
        return ProjectSummary(id: 1, title: "NLP report", openTaskCount: count, nearestDeadline: deadline)
    }

    @Test func rowShowsTaskCountAndNearestDay() {
        #expect(summary(3, "Oct 17 23:59").detail(at: now) == "3 tasks · Due Sat 17 Oct")
        #expect(summary(1, "Oct 20").detail(at: now) == "1 task · Due Tue 20 Oct")
        #expect(summary(1, "Oct 13 18:00").detail(at: now) == "1 task · Overdue Tue 13 Oct")
        #expect(summary(2, nil).detail(at: now) == "2 tasks · No deadline")
        #expect(summary(0, nil).detail(at: now) == "No open tasks")
    }

    @Test func headerShowsTheExactNearestDeadline() {
        #expect(summary(3, "Oct 17 23:59").headline(at: now) == "3 tasks · nearest deadline Sat 17 Oct, 23:59 · Bogotá")
        #expect(summary(1, "Oct 20").headline(at: now) == "1 task · nearest deadline Tue 20 Oct · Bogotá")
        #expect(summary(2, nil).headline(at: now) == "2 tasks · no deadline")
    }

    @Test func overdueIsReported() {
        #expect(summary(1, "Oct 13 18:00").isOverdue(at: now))
        #expect(!summary(1, "Oct 20").isOverdue(at: now))
    }
}
