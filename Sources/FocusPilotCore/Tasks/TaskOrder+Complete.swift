extension TaskOrder {
    /// The positions that change when the owner marks task `id` done.
    ///
    /// Completing the Now task is moving it out of Now, so the first task in
    /// Next becomes Now (owner decision, 2026-10-15); with none, Now stays
    /// empty. The completed task leaves Now before another enters it, so
    /// applying the changes in order never leaves two tasks in Now.
    public static func complete(_ id: Int64, in positions: [TaskPosition]) -> [TaskPosition] {
        guard var completed = positions.first(where: { $0.id == id }), completed.status != .done else { return [] }
        let wasNow = completed.status == .now
        completed.status = .done
        guard wasNow, let first = positions.filter({ $0.status == .next }).min(by: { ($0.rank, $0.id) < ($1.rank, $1.id) }) else {
            return [completed]
        }
        return [completed, TaskPosition(id: first.id, status: .now, rank: 0)]
    }
}
