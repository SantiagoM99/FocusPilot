import Foundation

/// One thing that needs the owner now (decision 0004).
public struct AttentionItem: Equatable, Sendable, Identifiable {
    public enum ID: Hashable, Sendable {
        case review(Int64), check(Int64), report(Int64)
    }

    public enum Kind: Sendable {
        /// An agent asking for approval or an answer.
        case approval
        /// An agent finished; its result is not reviewed yet.
        case finished
        /// A check the owner scheduled on a waiting task is due.
        case check
        /// A helper agent's report, maybe with a message to accept (#67).
        case report
    }

    /// An item quietly stands out once it has waited this long (decision 0004, proposed default).
    public static let alertAfter: TimeInterval = 30 * 60

    public var id: ID
    public var kind: Kind
    /// Nil for a report, which belongs to a project rather than a task.
    public var taskID: Int64?
    public var taskTitle: String
    public var projectTitle: String?
    public var agentLabel: String?
    /// The agent to open on Switch.
    public var linkID: Int64?
    /// What a waiting task waits on, for checks.
    public var waitingOn: String?
    /// When the owner was first needed: when FocusPilot saw the agent ask or
    /// finish, or the time the owner set for a check.
    public var waitingSince: Date
    /// The report, for `.report` items.
    public var report: AgentReport? = nil

    public func needsAlert(at now: Date) -> Bool {
        now.timeIntervalSince(waitingSince) >= Self.alertAfter
    }

    /// "ablation finished", "plots needs your approval", "Time to check on Ana's review".
    public var headline: String {
        switch kind {
        case .approval: "\(agentLabel ?? "An agent") needs your approval"
        case .finished: "\(agentLabel ?? "An agent") finished"
        case .check: "Time to check on \(waitingOn ?? taskTitle)"
        case .report:
            if let report, let proposal = report.proposal {
                "\(report.sourceLabel) proposes a message for \(proposal.target?.label ?? proposal.targetAsGiven)"
            } else {
                "\(report?.sourceLabel ?? "An agent") sent a report"
            }
        }
    }

    /// "Run ablation · NLP report"; a report's project, or "No project".
    public var place: String {
        if kind == .report { return projectTitle ?? "No project" }
        return ([taskTitle] + [projectTitle].compactMap(\.self)).joined(separator: " · ")
    }
}

/// Builds the attention queue: unreviewed agent results and approval
/// requests, and due checks, for open tasks only, and agent reports.
/// Ordered by priority (the task's place: Now, then Next, then Later), then
/// deadline (soonest first, none last), then how long it has waited
/// (longest first). A report has no task: it ranks with Now when its
/// project holds the Now task, else with Next, with no deadline. No limit.
public enum AttentionQueue {
    public static func items(tasks: [TodayItem], reviews: [ReviewItem], waiting: [TaskWaiting],
                             reports: [AgentReport] = [], now: Date) -> [AttentionItem] {
        let open = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let fromAgents = reviews.compactMap { review -> AttentionItem? in
            guard let task = open[review.taskID] else { return nil }
            return AttentionItem(id: .review(review.id), kind: review.kind == .approval ? .approval : .finished,
                                 taskID: task.id, taskTitle: task.title, projectTitle: task.projectTitle,
                                 agentLabel: review.agentLabel, linkID: review.linkID, waitingSince: review.occurredAt)
        }
        let checks = waiting.compactMap { mark -> AttentionItem? in
            guard let task = open[mark.taskID], let checkAt = mark.checkAt, mark.checkIsDue(at: now) else { return nil }
            return AttentionItem(id: .check(task.id), kind: .check, taskID: task.id, taskTitle: task.title,
                                 projectTitle: task.projectTitle, waitingOn: mark.on, waitingSince: checkAt)
        }
        let fromReports = reports.map { report in
            AttentionItem(id: .report(report.id), kind: .report, taskID: nil, taskTitle: "", projectTitle: report.projectTitle,
                          agentLabel: report.sourceLabel, waitingSince: report.receivedAt, report: report)
        }
        let nowProject = tasks.first { $0.status == .now }?.projectID
        return (fromAgents + checks + fromReports).sorted { lhs, rhs in
            let left = key(lhs, open, nowProject), right = key(rhs, open, nowProject)
            if left.priority != right.priority { return left.priority < right.priority }
            if left.deadline != right.deadline { return left.deadline < right.deadline }
            return lhs.waitingSince < rhs.waitingSince
        }
    }

    private static func key(_ item: AttentionItem, _ open: [Int64: TodayItem],
                            _ nowProject: Int64?) -> (priority: Int, deadline: Date) {
        if let report = item.report {
            return (report.projectID != nil && report.projectID == nowProject ? 0 : 1, .distantFuture)
        }
        let task = item.taskID.flatMap { open[$0] }
        let priority = switch task?.status {
        case .now: 0
        case .next: 1
        default: 2
        }
        return (priority, task?.deadline?.endInstant ?? .distantFuture)
    }
}

/// How long an item has waited, as rows and the floating panel show it.
public enum AttentionText {
    /// "Just now", "Waiting 34 min", "Waiting 1 h 5 min".
    public static func waited(_ item: AttentionItem, at now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(item.waitingSince) / 60)
        guard minutes >= 1 else { return "Just now" }
        if minutes < 60 { return "Waiting \(minutes) min" }
        return minutes % 60 == 0 ? "Waiting \(minutes / 60) h" : "Waiting \(minutes / 60) h \(minutes % 60) min"
    }

    /// The item as VoiceOver reads it, one sentence with units spelled out:
    /// "plots needs your approval, Run ablation, NLP report, waiting 34 minutes".
    public static func spoken(_ item: AttentionItem, at now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(item.waitingSince) / 60)
        let unit = { (count: Int, name: String) in "\(count) \(name)\(count == 1 ? "" : "s")" }
        let waited = switch (minutes / 60, minutes % 60) {
        case (0, 0): "just now"
        case (0, let rest): "waiting " + unit(rest, "minute")
        case (let hours, 0): "waiting " + unit(hours, "hour")
        case (let hours, let rest): "waiting " + unit(hours, "hour") + " " + unit(rest, "minute")
        }
        return [item.headline, item.taskTitle, item.projectTitle, waited].compactMap(\.self).joined(separator: ", ")
    }
}

/// When the app recomputes In flight and the queue as time passes: once a
/// minute while anything waits, since waiting times and due checks change by
/// the minute. Session countdowns keep their own one-second clock.
public enum AttentionClock {
    public static let interval: TimeInterval = 60

    public static func isDue(at now: Date, last: Date, somethingWaits: Bool) -> Bool {
        somethingWaits && now.timeIntervalSince(last) >= interval
    }
}
