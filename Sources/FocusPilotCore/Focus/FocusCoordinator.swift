import Foundation


/// Owns FocusPilot's state transitions and is the UI's single entry point.
///
/// The UI reads snapshots from here and sends requests here; the coordinator
/// talks to the repository. The current task is the one the owner pinned as
/// Now; nothing else changes it. Focus sessions are driven by `FocusEngine`
/// (see `FocusCoordinator+Sessions.swift`); every change is pushed to
/// `snapshots()` subscribers, so the menu bar stays current without the
/// planning window.
public actor FocusCoordinator {
    public enum SessionError: Error, Equatable {
        case noCurrentTask
    }

    private let herdr: (any HerdrWorkspaceSource)?

    let repository: TaskRepository
    let publisher: PolicyPublisher
    let notices: FocusNoticeSink
    let now: @Sendable () -> Date

    /// The latest session, active or ended.
    var session: FocusSession?
    /// When the owner first asked to end the current strict session early.
    var earlyEndRequestedAt: Date?
    private var subscribers: [UUID: AsyncStream<FocusSnapshot>.Continuation] = [:]

    /// Without `herdr`, Herdr reads as not installed.
    public init(repository: TaskRepository, herdr: (any HerdrWorkspaceSource)? = nil,
                publisher: PolicyPublisher = PolicyNotDelivered(),
                notices: FocusNoticeSink = NoticesIgnored(), now: @escaping @Sendable () -> Date = Date.init) {
        self.repository = repository
        self.herdr = herdr
        self.publisher = publisher
        self.notices = notices
        self.now = now
    }

    public func snapshot() async -> FocusSnapshot {
        FocusSnapshot(currentTaskTitle: try? await repository.nowTask()?.title, session: session,
                      earlyEndAvailableAt: earlyEndRequestedAt.map { $0.addingTimeInterval(StrictEarlyEnd.wait) })
    }

    /// Every snapshot from now on, starting with the current one.
    public func snapshots() async -> AsyncStream<FocusSnapshot> {
        let (stream, continuation) = AsyncStream.makeStream(of: FocusSnapshot.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { _ in Task { await self.unsubscribe(id) } }
        continuation.yield(await snapshot())
        return stream
    }

    private func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
    }

    func broadcast() async {
        guard !subscribers.isEmpty else { return }
        let latest = await snapshot()
        for continuation in subscribers.values {
            continuation.yield(latest)
        }
    }

    public func hasTasks() async throws -> Bool {
        try await !repository.tasks().isEmpty
    }

    // MARK: Tasks

    public func capture(_ newTask: NewTask) async throws {
        _ = try await repository.addTask(newTask)
        await broadcast()
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
        await broadcast()
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
