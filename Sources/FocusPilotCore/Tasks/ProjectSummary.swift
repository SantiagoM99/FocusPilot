import Foundation

/// One row of the Projects view: a project's open tasks and the deadline
/// that comes first. `id` is nil for the tasks filed under no project.
public struct ProjectSummary: Equatable, Sendable, Identifiable {
    public var id: Int64?
    public var title: String
    public var openTaskCount: Int
    public var nearestDeadline: Deadline?
    public var herdrLink: HerdrLink?

    public init(id: Int64?, title: String, openTaskCount: Int, nearestDeadline: Deadline?, herdrLink: HerdrLink? = nil) {
        self.id = id
        self.title = title
        self.openTaskCount = openTaskCount
        self.nearestDeadline = nearestDeadline
        self.herdrLink = herdrLink
    }

    /// "3 tasks · Due Sat 17 Oct", "1 task · Overdue Tue 13 Oct".
    public func detail(at now: Date) -> String {
        guard openTaskCount > 0 else { return "No open tasks" }
        return taskCount + " · " + (nearestDeadline.map { DeadlineText($0).dueDay(at: now) } ?? "No deadline")
    }

    /// "3 tasks · nearest deadline Sat 17 Oct, 23:59 · Bogotá".
    public func headline(at now: Date) -> String {
        guard openTaskCount > 0 else { return "No open tasks" }
        let deadline = nearestDeadline.map { "nearest deadline " + DeadlineText($0).dayTimeAndCity(at: now) }
        return taskCount + " · " + (deadline ?? "no deadline")
    }

    public func isOverdue(at now: Date) -> Bool {
        nearestDeadline?.isOverdue(at: now) == true
    }

    private var taskCount: String {
        openTaskCount == 1 ? "1 task" : "\(openTaskCount) tasks"
    }
}
