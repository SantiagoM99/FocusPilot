import Testing
@testable import FocusPilotCore

@Suite("TaskOrder")
struct TaskOrderTests {
    // Now: 1 · Next: 2, 3, 4 · Later: 5, 6
    private let board = [
        TaskPosition(id: 1, status: .now, rank: 0),
        TaskPosition(id: 2, status: .next, rank: 0),
        TaskPosition(id: 3, status: .next, rank: 1),
        TaskPosition(id: 4, status: .next, rank: 2),
        TaskPosition(id: 5, status: .later, rank: 0),
        TaskPosition(id: 6, status: .later, rank: 1),
    ]

    /// Applies the returned changes and lists each section's ids in order.
    private func sections(after changes: [TaskPosition]) -> [TaskStatus: [Int64]] {
        var byID = Dictionary(uniqueKeysWithValues: board.map { ($0.id, $0) })
        for change in changes { byID[change.id] = change }
        return Dictionary(grouping: byID.values.sorted { $0.rank < $1.rank }, by: \.status).mapValues { $0.map(\.id) }
    }

    @Test func pinningReturnsThePreviousNowToTheTopOfNext() {
        let changes = TaskOrder.move(5, to: .now, .top, in: board)

        #expect(sections(after: changes) == [.now: [5], .next: [1, 2, 3, 4], .later: [6]])
    }

    @Test func pinningWhenNothingIsNowOnlyMovesThatTask() {
        let withoutNow = board.filter { $0.id != 1 }

        let changes = TaskOrder.move(3, to: .now, .top, in: withoutNow)

        #expect(changes == [TaskPosition(id: 3, status: .now, rank: 0)])
    }

    @Test func demotionsComeFirstSoTheDatabaseNeverHoldsTwoNows() {
        let changes = TaskOrder.move(5, to: .now, .top, in: board)

        #expect(changes.last == TaskPosition(id: 5, status: .now, rank: 0))
    }

    @Test(arguments: [
        (TaskPlacement.top, [4, 2, 3]),
        (.bottom, [2, 3, 4]),
        (.before(2), [4, 2, 3]),
        (.before(3), [2, 4, 3]),
        (.after(2), [2, 4, 3]),
    ])
    func movingWithinASectionPlacesTheTask(placement: TaskPlacement, expected: [Int64]) {
        let changes = TaskOrder.move(4, to: .next, placement, in: board)

        #expect(sections(after: changes)[.next] == expected)
    }

    @Test func movingToAnotherSectionLeavesTheRestInOrder() {
        let changes = TaskOrder.move(3, to: .later, .top, in: board)

        #expect(sections(after: changes) == [.now: [1], .next: [2, 4], .later: [3, 5, 6]])
    }

    // Owner decision on PR #32: the first task in Next takes the place of a
    // Now task the owner moves away.
    @Test func movingTheNowTaskAwayPromotesTheFirstNextTask() {
        let changes = TaskOrder.move(1, to: .later, .bottom, in: board)

        #expect(sections(after: changes) == [.now: [2], .next: [3, 4], .later: [5, 6, 1]])
        #expect(changes.last == TaskPosition(id: 2, status: .now, rank: 0))
    }

    @Test func theMovedNowTaskIsNotPromotedBackIntoNow() {
        let changes = TaskOrder.move(1, to: .next, .top, in: board)

        #expect(sections(after: changes) == [.now: [2], .next: [1, 3, 4], .later: [5, 6]])
    }

    @Test func movingTheNowTaskAwayWithNothingInNextLeavesNoNow() {
        let onlyLater = board.filter { $0.status != .next }

        let changes = TaskOrder.move(1, to: .later, .top, in: onlyLater)

        #expect(changes.allSatisfy { $0.status != .now })
        #expect(changes.contains(TaskPosition(id: 1, status: .later, rank: 0)))
    }

    @Test func movingTheNowTaskToNextWhenNextIsEmptyLeavesNoNow() {
        let onlyLater = board.filter { $0.status != .next }

        let changes = TaskOrder.move(1, to: .next, .top, in: onlyLater)

        #expect(changes == [TaskPosition(id: 1, status: .next, rank: 0)])
    }

    @Test func onlyChangedTasksAreReturned() {
        // Moving 3 up past 2 swaps them; 4 and the other sections are untouched.
        let changes = TaskOrder.move(3, to: .next, .before(2), in: board)

        #expect(Set(changes.map(\.id)) == [2, 3])
    }

    @Test func aMoveThatChangesNothingReturnsNothing() {
        #expect(TaskOrder.move(2, to: .next, .top, in: board).isEmpty)
        #expect(TaskOrder.move(1, to: .now, .top, in: board).isEmpty)
    }

    @Test func unknownTasksAndDoneAreLeftAlone() {
        #expect(TaskOrder.move(99, to: .next, .top, in: board).isEmpty)
        #expect(TaskOrder.move(2, to: .done, .top, in: board).isEmpty)
    }
}

@Suite("TaskSections")
struct TaskSectionsTests {
    private func item(_ id: Int64, _ status: TaskStatus) -> TodayItem {
        TodayItem(id: id, title: "Task \(id)", status: status)
    }

    @Test func itemsAreGroupedKeepingTheirOrder() {
        let sections = TaskSections([item(1, .now), item(3, .next), item(2, .next), item(4, .later)])

        #expect(sections.now?.id == 1)
        #expect(sections.next.map(\.id) == [3, 2])
        #expect(sections.later.map(\.id) == [4])
        #expect(sections.items(in: .next).map(\.id) == [3, 2])
    }
}

@Suite("TaskPlacement from the visible list")
struct VisiblePlacementTests {
    // A section as shown: in a project view, other projects' tasks are hidden.
    private let visible: [Int64] = [10, 20, 30]

    @Test func movingUpGoesBeforeThePreviousVisibleTask() {
        #expect(TaskPlacement.up(20, in: visible) == .before(10))
        #expect(TaskPlacement.up(10, in: visible) == nil)
    }

    @Test func movingDownGoesAfterTheNextVisibleTask() {
        #expect(TaskPlacement.down(20, in: visible) == .after(30))
        #expect(TaskPlacement.down(30, in: visible) == nil)
    }

    // SwiftUI's onMove offset counts the dragged row itself.
    @Test(arguments: [
        (0, 3, TaskPlacement.after(30)),
        (0, 2, .before(30)),
        (2, 0, .before(10)),
        (1, 0, .before(10)),
    ])
    func dropOffsetsBecomePlacements(source: Int, offset: Int, expected: TaskPlacement) {
        #expect(TaskPlacement.drop(visible[source], at: offset, in: visible) == expected)
    }

    @Test func movingToTheTopOfASectionIsNilWhenAlreadyThere() {
        #expect(TaskPlacement.toTop(of: .next, moving: 10, from: .next, visible: visible) == nil)
        #expect(TaskPlacement.toTop(of: .next, moving: 20, from: .next, visible: visible) == .top)
        #expect(TaskPlacement.toTop(of: .later, moving: 10, from: .next, visible: []) == .top)
        #expect(TaskPlacement.toTop(of: .now, moving: 10, from: .now, visible: [10]) == nil)
    }

    @Test func droppingARowWhereItWasChangesNothing() {
        #expect(TaskPlacement.drop(20, at: 1, in: visible) == nil)
        #expect(TaskPlacement.drop(20, at: 2, in: visible) == nil)
    }
}
