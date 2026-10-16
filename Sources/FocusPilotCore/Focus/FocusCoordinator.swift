/// Owns FocusPilot's state transitions and is the UI's single entry point.
///
/// The UI reads snapshots from here and sends requests here; the coordinator
/// talks to the repository. The current task is the one the owner pinned as
/// Now; nothing else changes it.
public actor FocusCoordinator {
    // Held so that later state transitions persist through the sole writer
    // rather than each feature opening its own path to the database.
    private let repository: TaskRepository
    private let herdr: (any HerdrWorkspaceSource)?

    private var current = FocusSnapshot()

    /// Without `herdr`, Herdr reads as not installed.
    public init(repository: TaskRepository, herdr: (any HerdrWorkspaceSource)? = nil) {
        self.repository = repository
        self.herdr = herdr
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

    // MARK: Herdr workspaces

    /// Reads Herdr's workspaces and links the new ones to projects. Nothing
    /// is written while Herdr is unreachable, and a failed write is retried
    /// on the next refresh, since unseen workspaces stay unseen.
    public func refreshHerdr() async -> HerdrConnection {
        guard let herdr else { return .disconnected(.binaryNotFound) }
        let connection = await herdr.connection()
        if case .connected(let server, let workspaces) = connection {
            _ = try? await repository.syncHerdrWorkspaces(workspaces, on: server)
        }
        return connection
    }

    public func importHerdrWorkspaces(_ workspaces: [HerdrWorkspace], on server: HerdrServer) async throws {
        try await repository.importHerdrWorkspaces(workspaces, on: server)
    }

    public func linkProject(_ projectID: Int64, to workspace: HerdrWorkspace, on server: HerdrServer) async throws {
        try await repository.linkProject(projectID, to: workspace, on: server)
    }

    public func unlinkProject(_ projectID: Int64) async throws {
        try await repository.unlinkProject(projectID)
    }
}
