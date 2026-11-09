import Foundation

/// A thread the owner does not need to act on yet.
public enum ThreadState: Sendable {
    case working, waiting
}

/// An agent working on a task, or a task the owner marked waiting.
public struct InFlightThread: Equatable, Sendable, Identifiable {
    public enum ID: Hashable, Sendable {
        case agent(Int64), waiting(Int64)
    }

    public var id: ID
    public var taskID: Int64
    public var taskTitle: String
    /// The agent's label.
    public var label: String
    public var state: ThreadState
    /// Since when it has been in this state, as FocusPilot saw it.
    public var since: Date
    /// The agent to open, for agent threads.
    public var linkID: Int64?
    public var waitingOn: String?
    /// When the owner wants to check on a waiting thread.
    public var checkAt: Date?
}

/// One row of In flight or the Review queue (redesign, InFlight board).
public struct InFlightRow: Equatable, Sendable, Identifiable {
    public enum ID: Hashable, Sendable {
        case attention(AttentionItem.ID), thread(InFlightThread.ID)
    }

    public enum Source: Equatable, Sendable {
        case attention(AttentionItem), thread(InFlightThread)
    }

    public enum Status: Sendable {
        case resultsReady, approval, check, report, working, waiting
    }

    public enum Action: Sendable {
        case switchTo, openAgent, stopWaiting
    }

    public var source: Source
    public var status: Status
    public var title: String
    /// "NLP report · Herdr · Results ready · 12 min ago".
    public var detail: String
    /// "Results ready · Herdr", for the inspector.
    public var statusLine: String

    public var id: ID {
        switch source {
        case .attention(let item): .attention(item.id)
        case .thread(let thread): .thread(thread.id)
        }
    }

    public var linkID: Int64? {
        switch source {
        case .attention(let item): item.linkID
        case .thread(let thread): thread.linkID
        }
    }

    /// The row's one button; a running row has none, as the board draws it.
    public var action: Action? {
        switch status {
        case .resultsReady, .check: .switchTo
        case .approval: linkID == nil ? .switchTo : .openAgent
        case .waiting: .stopWaiting
        case .report, .working: nil
        }
    }

    /// Nil for a report, which has no task to switch to.
    public var switchRequest: SwitchRequest? {
        switch source {
        case .attention(let item): SwitchRequest(item)
        case .thread(let thread): SwitchRequest(thread)
        }
    }

    /// The row the inspector shows: the selected one while it exists, else
    /// the first, so a row that leaves the list does not empty the inspector.
    public static func selected(_ id: ID?, in rows: [InFlightRow]) -> InFlightRow? {
        rows.first { $0.id == id } ?? rows.first
    }
}

/// In flight's three sections, each ordered by the task's place, its
/// deadline, then the longest wait. There is no limit on rows.
public struct InFlightBoard: Equatable, Sendable {
    public var waitingOnYou: [InFlightRow] = []
    public var running: [InFlightRow] = []
    public var waiting: [InFlightRow] = []

    public init() {}

    public var rows: [InFlightRow] { waitingOnYou + running + waiting }

    /// The Review queue: finished results nobody has reviewed. Approvals
    /// wait in In flight, since they are answered in the agent.
    public var results: [InFlightRow] { waitingOnYou.filter { $0.status == .resultsReady } }
}

/// Builds In flight from what is stored. A task is in flight when it moves
/// without the owner: a linked agent is working, asking or has a result
/// waiting, or the owner marked the task waiting. Only open tasks count.
public enum InFlight {
    public static func board(tasks: [TodayItem], links: [TaskAgentLink], reviews: [ReviewItem], waiting: [TaskWaiting],
                             reports: [AgentReport] = [], now: Date, timeZone: TimeZone = .current) -> InFlightBoard {
        let open = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let attention = AttentionQueue.items(tasks: tasks, reviews: reviews, waiting: waiting, reports: reports, now: now)
        let working = links.compactMap { link in
            open[link.taskID].flatMap { link.lastStatus == .working ? thread(link, $0) : nil }
        }
        let held = waiting.compactMap { mark in
            open[mark.taskID].flatMap { mark.checkIsDue(at: now) ? nil : thread(mark, $0) }
        }
        let text = RowText(now: now, timeZone: timeZone, projects: open.mapValues(\.projectTitle),
                           agentsOnTask: agentCounts(attention, working))
        var board = InFlightBoard()
        board.waitingOnYou = attention.map(text.row)
        board.running = sorted(working, open).map(text.row)
        board.waiting = sorted(held, open).map(text.row)
        return board
    }

    private static func thread(_ link: TaskAgentLink, _ task: TodayItem) -> InFlightThread {
        InFlightThread(id: .agent(link.id), taskID: task.id, taskTitle: task.title, label: link.label,
                       state: .working, since: link.statusChangedAt, linkID: link.id)
    }

    private static func thread(_ mark: TaskWaiting, _ task: TodayItem) -> InFlightThread {
        InFlightThread(id: .waiting(task.id), taskID: task.id, taskTitle: task.title, label: "Waiting",
                       state: .waiting, since: mark.since, waitingOn: mark.on, checkAt: mark.checkAt)
    }

    private static func agentCounts(_ attention: [AttentionItem], _ working: [InFlightThread]) -> [Int64: Int] {
        var linksByTask: [Int64: Set<Int64>] = [:]
        for item in attention {
            if let task = item.taskID, let link = item.linkID { linksByTask[task, default: []].insert(link) }
        }
        for thread in working {
            if let link = thread.linkID { linksByTask[thread.taskID, default: []].insert(link) }
        }
        return linksByTask.mapValues(\.count)
    }

    private static func sorted(_ threads: [InFlightThread], _ open: [Int64: TodayItem]) -> [InFlightThread] {
        threads.sorted { lhs, rhs in
            let left = AttentionQueue.rank(open[lhs.taskID]), right = AttentionQueue.rank(open[rhs.taskID])
            if left.priority != right.priority { return left.priority < right.priority }
            if left.deadline != right.deadline { return left.deadline < right.deadline }
            return lhs.since < rhs.since
        }
    }
}

/// The boards' wording for each kind of row.
private struct RowText {
    static let herdr = "Herdr"

    let now: Date
    let timeZone: TimeZone
    let projects: [Int64: String?]
    let agentsOnTask: [Int64: Int]

    func row(_ item: AttentionItem) -> InFlightRow {
        let ago = agoText(since: item.waitingSince)
        switch item.kind {
        case .approval, .finished:
            let status = item.kind == .approval ? "Approval requested" : "Results ready"
            return InFlightRow(source: .attention(item), status: item.kind == .approval ? .approval : .resultsReady,
                               title: item.taskTitle,
                               detail: joined(item.projectTitle, agent(item.agentLabel, onTask: item.taskID), status, ago),
                               statusLine: joined(status, Self.herdr))
        case .check:
            return InFlightRow(source: .attention(item), status: .check, title: item.taskTitle,
                               detail: joined(item.projectTitle, "Check due", item.waitingOn, ago),
                               statusLine: joined("Check due", item.waitingOn))
        case .report:
            return InFlightRow(source: .attention(item), status: .report, title: item.headline,
                               detail: joined(item.projectTitle, "Report", ago),
                               statusLine: joined("Report", item.projectTitle))
        }
    }

    func row(_ thread: InFlightThread) -> InFlightRow {
        let project = projects[thread.taskID] ?? nil
        switch thread.state {
        case .working:
            return InFlightRow(source: .thread(thread), status: .working, title: thread.taskTitle,
                               detail: joined(project, agent(thread.label, onTask: thread.taskID), "Working",
                                              durationText(since: thread.since)),
                               statusLine: joined("Working", Self.herdr))
        case .waiting:
            let line = thread.checkAt.map { "Until \(untilText($0))" } ?? "Waiting \(durationText(since: thread.since))"
            return InFlightRow(source: .thread(thread), status: .waiting, title: thread.taskTitle,
                               detail: joined(project, line, thread.waitingOn), statusLine: joined(line, thread.waitingOn))
        }
    }

    /// "Herdr", or the agent's name when the task has several.
    private func agent(_ label: String?, onTask taskID: Int64?) -> String {
        guard let taskID, agentsOnTask[taskID, default: 0] > 1, let label else { return Self.herdr }
        return label
    }

    private func joined(_ parts: String?...) -> String {
        parts.compactMap(\.self).joined(separator: " · ")
    }

    /// "12 min ago", "2 h 5 min ago", "Just now".
    private func agoText(since: Date) -> String {
        let minutes = Int(now.timeIntervalSince(since) / 60)
        return minutes < 1 ? "Just now" : "\(duration(minutes)) ago"
    }

    /// "41 min", "2 h 5 min".
    private func durationText(since: Date) -> String {
        duration(max(1, Int(now.timeIntervalSince(since) / 60)))
    }

    private func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    /// "Thu 09:00".
    private func untilText(_ date: Date) -> String {
        date.formatted(Date.VerbatimFormatStyle(
            format: "\(weekday: .abbreviated) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            locale: Locale(identifier: "en_US_POSIX"), timeZone: timeZone, calendar: Calendar(identifier: .gregorian)))
    }
}
