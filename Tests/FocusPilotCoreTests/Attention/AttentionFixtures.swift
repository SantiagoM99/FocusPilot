import Foundation
@testable import FocusPilotCore

/// Tasks, agent links and review items for In flight and the attention
/// queue, built in memory (#57).
enum Attention {
    static let now = wednesdayMorningInBogota

    static func minutes(_ value: Double) -> Date { now.addingTimeInterval(value * 60) }

    static func task(_ id: Int64, _ title: String, project: (Int64, String)? = nil, status: TaskStatus = .next,
                     due: Date? = nil) -> TodayItem {
        TodayItem(id: id, title: title, status: status, projectTitle: project?.1, projectID: project?.0,
                  deadline: due.map { Deadline(due: .timed($0), timeZone: bogota, originalText: "due") })
    }

    static func link(_ id: Int64, task: Int64, _ label: String, _ status: HerdrAgentStatus?, since: Date = minutes(-60)) -> TaskAgentLink {
        TaskAgentLink(id: id, taskID: task, server: herdrServer, paneID: "w4:p\(id)", workspaceID: "w4", tabID: "w4:t1",
                      name: label, kind: "claude", label: label, workspaceLabel: nil, lastStatus: status,
                      statusChangedAt: since)
    }

    static func review(_ id: Int64, link: Int64, task: Int64, _ kind: AgentTransition.Review, at: Date,
                       title: String = "task", agent: String = "agent") -> ReviewItem {
        ReviewItem(id: id, taskID: task, taskTitle: title, linkID: link, kind: kind, occurredAt: at, agentLabel: agent,
                   workspaceLabel: nil, summary: nil, output: nil)
    }

    static let nlp: (Int64, String) = (1, "NLP report")
    static let app: (Int64, String) = (2, "FocusPilot")
}
