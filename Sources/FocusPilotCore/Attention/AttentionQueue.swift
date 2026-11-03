import Foundation

/// One thing that needs the owner now (decision 0004).
public struct AttentionItem: Equatable, Sendable, Identifiable {
    public enum ID: Hashable, Sendable {
        case review(Int64), check(Int64)
    }

    public enum Kind: Sendable {
        /// An agent asking for approval or an answer.
        case approval
        /// An agent finished; its result is not reviewed yet.
        case finished
        /// A check the owner scheduled on a waiting task is due.
        case check
    }

    /// An item quietly stands out once it has waited this long (decision 0004, proposed default).
    public static let alertAfter: TimeInterval = 30 * 60

    public var id: ID
    public var kind: Kind
    public var taskID: Int64
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

    public func needsAlert(at now: Date) -> Bool {
        now.timeIntervalSince(waitingSince) >= Self.alertAfter
    }

    /// "ablation finished", "plots needs your approval", "Time to check on Ana's review".
    public var headline: String {
        switch kind {
        case .approval: "\(agentLabel ?? "An agent") needs your approval"
        case .finished: "\(agentLabel ?? "An agent") finished"
        case .check: "Time to check on \(waitingOn ?? taskTitle)"
        }
    }

    /// "Run ablation · NLP report".
    public var place: String {
        ([taskTitle] + [projectTitle].compactMap(\.self)).joined(separator: " · ")
    }
}

/// Builds the attention queue: unreviewed agent results and approval
/// requests, and due checks, for open tasks only. Ordered by priority (the
/// task's place: Now, then Next, then Later), then deadline (soonest first,
/// none last), then how long it has waited (longest first). No limit.
public enum AttentionQueue {
    public static func items(tasks: [TodayItem], reviews: [ReviewItem], waiting: [TaskWaiting],
                             now: Date) -> [AttentionItem] {
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
        return (fromAgents + checks).sorted { lhs, rhs in
            let left = key(lhs, open), right = key(rhs, open)
            if left.priority != right.priority { return left.priority < right.priority }
            if left.deadline != right.deadline { return left.deadline < right.deadline }
            return lhs.waitingSince < rhs.waitingSince
        }
    }

    private static func key(_ item: AttentionItem, _ open: [Int64: TodayItem]) -> (priority: Int, deadline: Date) {
        let task = open[item.taskID]
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
