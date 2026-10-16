import GRDB

/// One row of the Today list: a task with its project's title.
public struct TodayItem: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var title: String
    public var status: TaskStatus
    public var projectTitle: String?
    public var nextAction: String?
    public var deadline: Deadline?

    public init(id: Int64, title: String, status: TaskStatus = .next, projectTitle: String? = nil,
                nextAction: String? = nil, deadline: Deadline? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.projectTitle = projectTitle
        self.nextAction = nextAction
        self.deadline = deadline
    }
}

/// The shape GRDB decodes from a task joined with its optional project.
struct TaskWithProject: Decodable, FetchableRecord {
    var task: TaskRecord
    var project: ProjectRecord?

    var todayItem: TodayItem {
        TodayItem(id: task.id!, title: task.title, status: task.status, projectTitle: project?.title,
                  nextAction: task.nextAction, deadline: task.deadline)
    }
}
