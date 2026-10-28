import Foundation
import GRDB

/// One row of the Today list: a task with its project's title.
public struct TodayItem: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var title: String
    public var status: TaskStatus
    public var projectTitle: String?
    public var projectID: Int64?
    public var nextAction: String?
    public var deadline: Deadline?
    /// Added with the focuspilot CLI from a Herdr pane; the owner can undo it.
    public var isFromHerdr: Bool
    public var wrapUp: TaskWrapUp?

    public init(id: Int64, title: String, status: TaskStatus = .next, projectTitle: String? = nil,
                projectID: Int64? = nil, nextAction: String? = nil, deadline: Deadline? = nil, isFromHerdr: Bool = false,
                wrapUp: TaskWrapUp? = nil) {
        self.projectID = projectID
        self.id = id
        self.title = title
        self.status = status
        self.projectTitle = projectTitle
        self.nextAction = nextAction
        self.deadline = deadline
        self.isFromHerdr = isFromHerdr
        self.wrapUp = wrapUp
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

extension TodayItem {
    /// A task row as VoiceOver reads it, one item: "PhD shortlist,
    /// Applications, due Tuesday 20 October". The project is left out inside
    /// a project, as on screen.
    public func spokenLabel(showsProject: Bool, at now: Date) -> String {
        [title, showsProject ? projectTitle : nil, deadline.map { DeadlineText($0).spoken(at: now) } ?? "no deadline",
         isFromHerdr ? "added from Herdr" : nil]
            .compactMap(\.self).joined(separator: ", ")
    }
}

/// The shape GRDB decodes from a task joined with its optional project.
struct TaskWithProject: Decodable, FetchableRecord {
    var task: TaskRecord
    var project: ProjectRecord?

    func todayItem(wrapUp: TaskWrapUp?) -> TodayItem {
        TodayItem(id: task.id!, title: task.title, status: task.status, projectTitle: project?.title,
                  projectID: task.projectId,
                  nextAction: task.nextAction, deadline: task.deadline, isFromHerdr: task.isFromHerdr,
                  wrapUp: wrapUp)
    }

    /// Today items with each task's latest wrap-up.
    static func todayItems(_ rows: [TaskWithProject], _ db: Database) throws -> [TodayItem] {
        let latest = try WrapUpRecord.latest(forTasks: rows.map { $0.task.id! }, db)
        return rows.map { $0.todayItem(wrapUp: latest[$0.task.id!]) }
    }
}
