import Foundation

/// What a thread is doing, as In flight shows it (decision 0004).
public enum ThreadState: Sendable {
    case working
    /// An agent asking for approval, or a check the owner scheduled is due.
    case needsYou
    /// An agent finished and the owner has not reviewed the result.
    case finished
    case waiting
}

/// One thread: an agent linked to a task, or a task the owner marked waiting.
public struct InFlightThread: Equatable, Sendable, Identifiable {
    public enum ID: Hashable, Sendable {
        case agent(Int64), waiting(Int64)
    }

    public var id: ID
    public var taskID: Int64
    public var taskTitle: String
    /// The agent's label, or "Waiting on Ana's review".
    public var label: String
    public var state: ThreadState
    /// Since when it has been in this state, as FocusPilot saw it.
    public var since: Date
    /// The agent to open on Switch, for agent threads.
    public var linkID: Int64?
    /// When the owner wants to check on a waiting thread.
    public var checkAt: Date?
}

/// A project's threads, for one collapsed group.
public struct InFlightProject: Equatable, Sendable, Identifiable {
    /// Nil for tasks with no project.
    public var id: Int64?
    public var title: String
    public var threads: [InFlightThread]

    public var needsYou: Int {
        threads.count { $0.state == .needsYou }
    }

    /// "NLP report · 5 threads · 2 need you".
    public var summary: String {
        var parts = [title, threads.count == 1 ? "1 thread" : "\(threads.count) threads"]
        if needsYou > 0 { parts.append(needsYou == 1 ? "1 needs you" : "\(needsYou) need you") }
        return parts.joined(separator: " · ")
    }
}

/// Builds In flight from what is stored. A task is in flight when it moves
/// without the owner: a linked agent is working, asking or has a result
/// waiting, or the owner marked the task waiting. Only open tasks count, and
/// there is no limit on threads.
public enum InFlight {
    public static func projects(tasks: [TodayItem], links: [TaskAgentLink], reviews: [ReviewItem],
                                waiting: [TaskWaiting], now: Date) -> [InFlightProject] {
        let open = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let agentThreads = links.compactMap { link in open[link.taskID].flatMap { thread(link, $0, reviews) } }
        let waitingThreads = waiting.compactMap { mark in open[mark.taskID].map { thread(mark, $0, now) } }
        let byProject = Dictionary(grouping: agentThreads + waitingThreads) { open[$0.taskID]?.projectID }
        return byProject.map { projectID, threads in
            InFlightProject(id: projectID, title: threads.first.flatMap { open[$0.taskID]?.projectTitle } ?? "No project",
                            threads: threads.sorted(by: order))
        }
        .sorted { lhs, rhs in
            // As the Projects list: alphabetical, "No project" last.
            if (lhs.id == nil) != (rhs.id == nil) { return rhs.id == nil }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private static func thread(_ link: TaskAgentLink, _ task: TodayItem, _ reviews: [ReviewItem]) -> InFlightThread? {
        let pending = reviews.filter { $0.linkID == link.id }
        let state: ThreadState
        var since = link.statusChangedAt
        switch link.lastStatus {
        case .blocked:
            state = .needsYou
            since = pending.first { $0.kind == .approval }?.occurredAt ?? since
        case .working:
            state = .working
        case .idle, .done:
            guard let result = pending.filter({ $0.kind == .finished }).map(\.occurredAt).max() else { return nil }
            state = .finished
            since = result
        case .unknown, nil:
            return nil
        }
        return InFlightThread(id: .agent(link.id), taskID: task.id, taskTitle: task.title, label: link.label,
                              state: state, since: since, linkID: link.id)
    }

    private static func thread(_ mark: TaskWaiting, _ task: TodayItem, _ now: Date) -> InFlightThread {
        InFlightThread(id: .waiting(task.id), taskID: task.id, taskTitle: task.title,
                       label: mark.on.map { "Waiting on \($0)" } ?? "Waiting",
                       state: mark.checkIsDue(at: now) ? .needsYou : .waiting, since: mark.since, checkAt: mark.checkAt)
    }

    /// Needs you, finished, working, waiting; then the longest in its state first.
    private static func order(_ lhs: InFlightThread, _ rhs: InFlightThread) -> Bool {
        func rank(_ state: ThreadState) -> Int {
            switch state {
            case .needsYou: 0
            case .finished: 1
            case .working: 2
            case .waiting: 3
            }
        }
        if rank(lhs.state) != rank(rhs.state) { return rank(lhs.state) < rank(rhs.state) }
        return lhs.since < rhs.since
    }
}
