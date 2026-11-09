import Foundation
import os


/// Owns FocusPilot's state transitions and is the UI's single entry point.
///
/// The UI reads snapshots from here and sends requests here; the coordinator
/// talks to the repository. The current task is the one the owner pinned as
/// Now; nothing else changes it. A session follows Now (#56). Focus sessions are driven by `FocusEngine`
/// (see `FocusCoordinator+Sessions.swift`); every change is pushed to
/// `snapshots()` subscribers, so the menu bar stays current without the
/// planning window.
public actor FocusCoordinator {
    public enum SessionError: Error, Equatable {
        case noCurrentTask
        /// A project chosen for a session is no longer there.
        case unknownProject
        /// A wrap-up or Done was asked for a session or task still in focus.
        case sessionStillActive
    }

    let herdr: (any HerdrWorkspaceSource)?
    let agents: (any HerdrAgentSource)?
    let folders: any FolderAccess

    let repository: TaskRepository
    let publisher: PolicyPublisher
    let notices: FocusNoticeSink
    let now: @Sendable () -> Date
    /// A monotonic clock for waits, so changing the Mac's clock cannot skip them.
    let uptime: @Sendable () -> Duration

    /// The latest session, active or ended.
    var session: FocusSession?
    /// The last policy published, shown in Settings.
    var policy: CompiledPolicy?
    /// When observe-only mode started, as of that policy.
    var observeSince: Date?
    /// The owner confirmed ending the current strict session early.
    var earlyEnd: StrictWait<UUID>?
    /// The owner confirmed a rule change that weakens the strict session.
    var ruleWait: StrictWait<ConfirmedRuleEdit>?
    /// The owner confirmed an exception request during a strict session.
    var exceptionWait: StrictWait<ExceptionRequest>?
    /// Reports whose Accept is running, so a second click cannot send again.
    var acceptingReports: Set<Int64> = []
    /// The socket's per-pane report limit, applied to queued reports by
    /// the time they were sent, since anyone can write the inbox file.
    var queuedReportLimit = AddRateLimit()
    /// The reason given when `exceptionWait` was confirmed; asking again
    /// from another profile or the app need not type it again.
    var exceptionWaitReason: String?
    /// The last queued session step; see `oneSessionStepAtATime`.
    var sessionStep: Task<Void, Never>?
    /// The last queued read-and-record of Herdr's agents; see `oneAgentReadingAtATime`.
    var agentReading: Task<Void, Never>?
    /// Grows with every change, so the app can drop a snapshot older than one it has.
    private var revision = 0
    private var subscribers: [UUID: AsyncStream<FocusSnapshot>.Continuation] = [:]

    /// Without `herdr` and `agents`, Herdr reads as not installed.
    public init(repository: TaskRepository, herdr: (any HerdrWorkspaceSource)? = nil,
                agents: (any HerdrAgentSource)? = nil,
                folders: any FolderAccess = SystemFolderAccess(),
                publisher: PolicyPublisher = PolicyNotDelivered(),
                notices: FocusNoticeSink = NoticesIgnored(), now: @escaping @Sendable () -> Date = Date.init,
                uptime: @escaping @Sendable () -> Duration = FocusCoordinator.continuousUptime()) {
        self.repository = repository
        self.herdr = herdr
        self.agents = agents
        self.folders = folders
        self.publisher = publisher
        self.notices = notices
        self.now = now
        self.uptime = uptime
    }

    /// Time on `ContinuousClock`, which keeps counting while the Mac sleeps.
    public static func continuousUptime() -> @Sendable () -> Duration {
        let origin = ContinuousClock.now
        return { ContinuousClock.now - origin }
    }

    public func snapshot() async -> FocusSnapshot {
        FocusSnapshot(currentTaskTitle: try? await repository.nowTask()?.title, session: session,
                      observeSince: observeSince, earlyEndAvailableAt: earlyEndAvailableAt(), policy: policy,
                      pendingRuleEdit: pendingRuleEdit(), pendingException: pendingException(),
                      revision: revision)
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
        revision += 1
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
        await followNowAfterTaskChange()
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
        await followNowAfterTaskChange()
        await broadcast()
    }

    /// The owner's Done. A task a session is running on ends through that
    /// session's Complete, so its wrap-up is not lost.
    public func completeTask(_ id: Int64) async throws {
        if let current = session, !current.hasEnded, current.taskID == id {
            throw SessionError.sessionStillActive
        }
        try await repository.completeTask(id)
        await followNowAfterTaskChange()
        await broadcast()
    }

    public func projects() async throws -> [ProjectSummary] {
        try await repository.projects()
    }

    public func projectTasks(_ projectID: Int64?) async throws -> [TodayItem] {
        try await repository.projectTasks(projectID)
    }

    // MARK: Herdr workspaces

    private static let herdrLog = Logger(subsystem: "com.santiagom99.FocusPilot", category: "herdr")

    /// Reads Herdr's workspaces and links the new ones to projects. Nothing
    /// is written while Herdr is unreachable, and a failed write is retried
    /// on the next refresh, since unseen workspaces stay unseen.
    public func refreshHerdr() async -> HerdrConnection {
        guard let herdr else { return .disconnected(.binaryNotFound) }
        let connection = await herdr.connection()
        if case .connected(let server, let workspaces) = connection {
            do {
                try await repository.syncHerdrWorkspaces(workspaces, on: server)
            } catch {
                Self.herdrLog.error("Herdr sync failed, retrying on the next refresh: \(error.localizedDescription)")
            }
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

    // MARK: Tasks from the focuspilot CLI

    /// The owner's undo of a task added from Herdr. The task a session is
    /// running on is refused, wherever it sits in the list.
    public func undoHerdrAdd(_ taskID: Int64) async throws {
        if let active = await snapshot().activeSession, active.taskID == taskID { throw HerdrTaskError.inRunningSession }
        // Its links go with it, so a session that allowed its pages must not keep them.
        let hadResources = try await repository.resources(forTask: taskID).contains { $0.owner == .task(taskID) }
        try await repository.undoHerdrAdd(taskID)
        if hadResources { await publish(try await repository.republish()) }
        await followNowAfterTaskChange()
    }

    /// Imports the adds and reports queued while FocusPilot was closed.
    /// Returns how many were handed on; already stored ones are not repeated.
    public func importInbox(_ inbox: TaskInbox) async throws -> Int {
        let repository = repository
        let imported = try await inbox.drain(isPermanent: { TaskRepository.isPermanentAddFailure($0) || $0 is ReportRefused },
                                             reports: { _ = try await self.receiveQueuedReport($0) }) {
            _ = try await repository.addFromHerdr($0)
        }.imported
        await followNowAfterTaskChange()
        return imported
    }
}
