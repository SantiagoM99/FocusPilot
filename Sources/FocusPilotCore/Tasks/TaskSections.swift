/// Today's or a project's tasks split into the Now task and the Next and
/// Later sections, each in manual order.
public struct TaskSections: Equatable, Sendable {
    public var now: TodayItem?
    public var next: [TodayItem]
    public var later: [TodayItem]

    public init(_ items: [TodayItem]) {
        now = items.first { $0.status == .now }
        next = items.filter { $0.status == .next }
        later = items.filter { $0.status == .later }
    }

    public func items(in status: TaskStatus) -> [TodayItem] {
        switch status {
        case .now: now.map { [$0] } ?? []
        case .next: next
        case .later: later
        case .done: []
        }
    }
}
