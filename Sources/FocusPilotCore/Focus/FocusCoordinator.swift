/// Owns FocusPilot's state transitions and is the UI's single entry point.
///
/// The UI reads snapshots from here and sends requests here; the coordinator
/// talks to the repository. Nothing selects a current task yet, so the
/// snapshot always reports none.
public actor FocusCoordinator {
    // Held so that later state transitions persist through the sole writer
    // rather than each feature opening its own path to the database.
    private let repository: TaskRepository

    private var current = FocusSnapshot()

    public init(repository: TaskRepository) {
        self.repository = repository
    }

    public func snapshot() -> FocusSnapshot {
        current
    }

    public func hasTasks() async throws -> Bool {
        try await !repository.tasks().isEmpty
    }
}
