/// Owns FocusPilot's state transitions and is the UI's single entry point.
///
/// The UI reads snapshots from here and sends requests here; the coordinator
/// talks to the repository. The current task is the one the owner pinned as
/// Now; nothing else changes it.
public actor FocusCoordinator {
    // Held so that later state transitions persist through the sole writer
    // rather than each feature opening its own path to the database.
    private let repository: TaskRepository

    private var current = FocusSnapshot()

    public init(repository: TaskRepository) {
        self.repository = repository
    }

    public func snapshot() async -> FocusSnapshot {
        var snapshot = current
        snapshot.currentTaskTitle = try? await repository.nowTask()?.title
        return snapshot
    }

    public func hasTasks() async throws -> Bool {
        try await !repository.tasks().isEmpty
    }

    // MARK: Tasks

    public func capture(_ newTask: NewTask) async throws {
        _ = try await repository.addTask(newTask)
    }

    public func todayTasks() async throws -> [TodayItem] {
        try await repository.todayTasks()
    }

    public func projectTitles() async throws -> [String] {
        try await repository.projectTitles()
    }

    /// Pins a task as Now or moves it within or between Next and Later.
    /// Only called for the owner's own actions.
    public func moveTask(_ id: Int64, to status: TaskStatus, _ placement: TaskPlacement) async throws {
        try await repository.moveTask(id, to: status, placement)
    }

    public func projects() async throws -> [ProjectSummary] {
        try await repository.projects()
    }

    public func projectTasks(_ projectID: Int64?) async throws -> [TodayItem] {
        try await repository.projectTasks(projectID)
    }
}
