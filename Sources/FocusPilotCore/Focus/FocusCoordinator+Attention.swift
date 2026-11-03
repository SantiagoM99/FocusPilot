import Foundation

/// In flight, the attention queue and Switch (#57, decision 0004). Nothing
/// here runs on its own: Switch is the owner's click, and it is the only
/// path that changes Now or opens an agent.
extension FocusCoordinator {
    /// The owner's Switch, in this order: the optional note becomes the
    /// current task's return cue (in the session's wrap-up history, or with
    /// no session outside one), the target becomes Now, then its agent opens
    /// if one is given. `handling` is the attention item the owner switched
    /// from: a result is then reviewed and a due check ends the wait; an
    /// approval stays until it is answered in Herdr. Returns what opening the
    /// agent did, or nil when none was asked.
    @discardableResult
    public func switchTo(_ target: Int64, note: String?, openingAgent linkID: Int64?,
                         handling item: AttentionItem.ID? = nil) async throws -> OpenAgentResult? {
        let current = try await repository.nowTask()
        if let current, current.id != target, let cue = note?.trimmingCharacters(in: .whitespacesAndNewlines), !cue.isEmpty {
            let active = session.flatMap { $0.hasEnded ? nil : $0.id }
            try await repository.saveReturnCue(cue, forTask: current.id, session: active)
        }
        if current?.id != target { try await moveTask(target, to: .now, .top) }
        switch item {
        case .review(let id):
            if try await repository.reviewQueue().contains(where: { $0.id == id && $0.kind == .finished }) {
                try await repository.markReviewed(id)
            }
        case .check(let taskID):
            try await repository.stopWaiting(taskID)
        case nil:
            break
        }
        var opened: OpenAgentResult?
        if let linkID { opened = await openAgent(linkID) }
        await broadcast()
        return opened
    }

    public func markWaiting(_ taskID: Int64, on: String?, checkAt: Date?) async throws {
        let on = on?.trimmingCharacters(in: .whitespacesAndNewlines)
        try await repository.markWaiting(taskID, on: on?.isEmpty == false ? on : nil, checkAt: checkAt)
        await broadcast()
    }

    public func stopWaiting(_ taskID: Int64) async throws {
        try await repository.stopWaiting(taskID)
        await broadcast()
    }

    /// The owner saw a due check and keeps waiting, with no new check.
    public func dismissCheck(_ taskID: Int64) async throws {
        try await repository.dismissCheck(taskID)
        await broadcast()
    }

    public func waitingTasks() async throws -> [TaskWaiting] {
        try await repository.waitingTasks()
    }

    /// The session's other open tasks for its wrap-up, in the order first
    /// touched; the task in Now at the end has its own fields.
    public func tasksTouched(by session: FocusSession) async throws -> [TodayItem] {
        try await repository.tasksTouched(in: session.id, excluding: session.taskID)
    }
}
