import GRDB

/// One row of the Today list: a task with its project's title.
public struct TodayItem: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var title: String
    public var status: TaskStatus
    public var projectTitle: String?
    public var nextAction: String?
    public var deadline: Deadline?
    /// Added with the focuspilot CLI from a Herdr pane; the owner can undo it.
    public var isFromHerdr: Bool

    public init(id: Int64, title: String, status: TaskStatus = .next, projectTitle: String? = nil,
                nextAction: String? = nil, deadline: Deadline? = nil, isFromHerdr: Bool = false) {
        self.id = id
        self.title = title
        self.status = status
        self.projectTitle = projectTitle
        self.nextAction = nextAction
        self.deadline = deadline
        self.isFromHerdr = isFromHerdr
    }
}

extension TodayItem {
    /// Whether the UI offers Undo: a task from Herdr still waiting in Next or
    /// Later, and not the one a session is running on. The repository and
    /// coordinator refuse the rest anyway.
    public func offersHerdrUndo(activeSessionTaskID: Int64?) -> Bool {
        isFromHerdr && (status == .next || status == .later) && id != activeSessionTaskID
    }
}

/// The shape GRDB decodes from a task joined with its optional project.
struct TaskWithProject: Decodable, FetchableRecord {
    var task: TaskRecord
    var project: ProjectRecord?

    var todayItem: TodayItem {
        TodayItem(id: task.id!, title: task.title, status: task.status, projectTitle: project?.title,
                  nextAction: task.nextAction, deadline: task.deadline, isFromHerdr: task.isFromHerdr)
    }
}
