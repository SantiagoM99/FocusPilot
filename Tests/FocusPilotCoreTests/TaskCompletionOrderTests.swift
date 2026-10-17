import Testing
@testable import FocusPilotCore

@Suite("TaskOrder completing a task")
struct TaskCompletionOrderTests {
    // Now: 1 · Next: 2, 3 · Later: 4
    private let board = [
        TaskPosition(id: 1, status: .now, rank: 0),
        TaskPosition(id: 2, status: .next, rank: 0),
        TaskPosition(id: 3, status: .next, rank: 1),
        TaskPosition(id: 4, status: .later, rank: 0),
    ]

    @Test func completingTheNowTaskPromotesTheFirstNextTaskAfterLeavingNow() {
        let changes = TaskOrder.complete(1, in: board)

        #expect(changes == [
            TaskPosition(id: 1, status: .done, rank: 0),
            TaskPosition(id: 2, status: .now, rank: 0),
        ])
    }

    @Test func completingTheNowTaskWithNothingInNextLeavesNowEmpty() {
        let changes = TaskOrder.complete(1, in: board.filter { $0.status != .next })

        #expect(changes == [TaskPosition(id: 1, status: .done, rank: 0)])
    }

    @Test func completingAnotherTaskOnlyMarksItDone() {
        #expect(TaskOrder.complete(3, in: board) == [TaskPosition(id: 3, status: .done, rank: 1)])
    }

    @Test func completingADoneOrUnknownTaskChangesNothing() {
        let done = board + [TaskPosition(id: 9, status: .done, rank: 0)]

        #expect(TaskOrder.complete(9, in: done).isEmpty)
        #expect(TaskOrder.complete(42, in: board).isEmpty)
    }
}
