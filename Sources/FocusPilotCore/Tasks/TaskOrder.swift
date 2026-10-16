/// A task's section and manual rank within it (lower comes first).
public struct TaskPosition: Equatable, Sendable {
    public var id: Int64
    public var status: TaskStatus
    public var rank: Int

    public init(id: Int64, status: TaskStatus, rank: Int) {
        self.id = id
        self.status = status
        self.rank = rank
    }
}

/// Where a moved task lands in its section.
public enum TaskPlacement: Equatable, Sendable {
    case top, bottom
    case before(Int64), after(Int64)
}

/// The owner's manual ordering, as a pure function of the current
/// positions, so `TaskRepository` can apply it inside one write.
public enum TaskOrder {
    /// The positions that change when task `id` moves to `status` at
    /// `placement`.
    ///
    /// Pinning a task as Now returns the previous Now to the top of Next.
    /// The target section is renumbered from 0, and only tasks whose status
    /// or rank changed are returned, demotions first, so applying them in
    /// order never leaves two tasks in Now. Moving to or from `done` is not
    /// an ordering change and returns nothing.
    public static func move(_ id: Int64, to status: TaskStatus, _ placement: TaskPlacement,
                            in positions: [TaskPosition]) -> [TaskPosition] {
        guard status != .done, let moving = positions.first(where: { $0.id == id }), moving.status != .done else {
            return []
        }
        var updated = Dictionary(uniqueKeysWithValues: positions.map { ($0.id, $0) })
        if status == .now {
            if let previous = positions.first(where: { $0.status == .now && $0.id != id }) {
                place(previous.id, in: .next, .top, &updated)
            }
            updated[id] = TaskPosition(id: id, status: .now, rank: 0)
        } else {
            place(id, in: status, placement, &updated)
        }
        return positions
            .compactMap { old in updated[old.id].flatMap { $0 == old ? nil : $0 } }
            .sorted { ($0.status == .now ? 1 : 0) < ($1.status == .now ? 1 : 0) }
    }

    private static func place(_ id: Int64, in status: TaskStatus, _ placement: TaskPlacement,
                              _ positions: inout [Int64: TaskPosition]) {
        var section = positions.values
            .filter { $0.status == status && $0.id != id }
            .sorted { ($0.rank, $0.id) < ($1.rank, $1.id) }
            .map(\.id)
        let index = switch placement {
        case .top: 0
        case .bottom: section.count
        case .before(let other): section.firstIndex(of: other) ?? section.count
        case .after(let other): section.firstIndex(of: other).map { $0 + 1 } ?? section.count
        }
        section.insert(id, at: index)
        for (rank, member) in section.enumerated() {
            positions[member] = TaskPosition(id: member, status: status, rank: rank)
        }
    }
}

/// Placements for moves made in a visible list, which in a project view
/// hides other projects' tasks: moves are relative to visible neighbors.
extension TaskPlacement {
    /// One row up, or nil at the top.
    public static func up(_ id: Int64, in visible: [Int64]) -> TaskPlacement? {
        guard let index = visible.firstIndex(of: id), index > 0 else { return nil }
        return .before(visible[index - 1])
    }

    /// One row down, or nil at the bottom.
    public static func down(_ id: Int64, in visible: [Int64]) -> TaskPlacement? {
        guard let index = visible.firstIndex(of: id), index < visible.count - 1 else { return nil }
        return .after(visible[index + 1])
    }

    /// A drag ending at SwiftUI's `onMove` offset, which counts the dragged
    /// row itself; nil when the row lands where it was.
    public static func drop(_ id: Int64, at offset: Int, in visible: [Int64]) -> TaskPlacement? {
        guard let source = visible.firstIndex(of: id) else { return nil }
        let destination = offset > source ? offset - 1 : offset
        guard destination != source else { return nil }
        let others = visible.filter { $0 != id }
        return destination < others.count ? .before(others[destination]) : .after(others[others.count - 1])
    }
}
