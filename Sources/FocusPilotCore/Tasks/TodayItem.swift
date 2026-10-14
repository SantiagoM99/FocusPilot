import GRDB

/// One row of the Today list: a task with its project's title.
public struct TodayItem: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var title: String
    public var projectTitle: String?
    public var nextAction: String?
    public var deadline: Deadline?
}

/// The shape GRDB decodes from a task joined with its optional project.
struct TaskWithProject: Decodable, FetchableRecord {
    var task: TaskRecord
    var project: ProjectRecord?

    var todayItem: TodayItem {
        TodayItem(id: task.id!, title: task.title, projectTitle: project?.title,
                  nextAction: task.nextAction, deadline: task.deadline)
    }
}
