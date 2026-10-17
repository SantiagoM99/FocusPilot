import AppKit
import FocusPilotCore
import Observation

/// Builds the long-lived core objects once and exposes what the views show.
@MainActor
@Observable
final class AppModel {
    private(set) var snapshot = FocusSnapshot()
    private(set) var today: [TodayItem] = []
    private(set) var projectTitles: [String] = []
    private(set) var projects: [ProjectSummary] = []
    /// The project shown in Projects (nil inside: tasks with no project).
    private(set) var shownProject: ProjectSummary.ID?
    private(set) var projectItems: [TodayItem] = []
    private(set) var startupError: String?
    private(set) var taskError: String?
    private(set) var commandLineError: String?
    /// What FocusPilot last saw of Herdr; nil until the first check.
    private(set) var herdr: HerdrConnection?
    /// Set when a session command fails; shown by the session surfaces.
    var sessionError: String?
    /// Asks the planning window to show the Start focus sheet.
    var isStartingFocus = false
    /// A strict session is ending early and every session surface shows the
    /// confirmation, wherever Complete was chosen.
    var isConfirmingEarlyEnd = false
    /// The wrap-up waiting for the owner; see `AppModel+WrapUp.swift`.
    var wrapUp: PendingWrapUp?
    /// Grows each time the planning window should come forward; `MenuBarIcon` opens it.
    var planningWindowRequests = 0
    /// When the owner last pressed Complete; their wrap-up may bring the window forward.
    @ObservationIgnored var ownerCompletedAt: Date?
    /// Pending reconcile at the next session deadline.
    @ObservationIgnored var reconcileTask: Task<Void, Never>?
    @ObservationIgnored lazy var focusPanel = FocusPanelController(model: self)
    let loginItem = LoginItemSettings(service: MainAppLoginItem())
    let menuBarPreferences = MenuBarPreferences()
    private let firstLaunch = FirstLaunchWelcome()

    let coordinator: FocusCoordinator?
    private var commandServer: CommandSocketServer?

    init() {
        do {
            let location = StorageLocation.applicationSupport()
            let repository = try TaskRepository(location: location)
            coordinator = FocusCoordinator(repository: repository, herdr: HerdrCLI(), notices: UserNotices())
            listenForCommands(location: location, service: CommandService(repository: repository))
        } catch {
            coordinator = nil
            startupError = "Could not open the database: \(error.localizedDescription)"
        }
        refreshLoginItem(on: NSMenu.didBeginTrackingNotification)
        refreshLoginItem(on: NSApplication.didBecomeActiveNotification)
        tickWhileTimeIsShown()
        watchHerdr()
        followSessions()
    }

    /// Answers the focuspilot CLI, and imports what it queued while the app
    /// was closed: at launch, then every few seconds in case an add was
    /// queued while the app was starting.
    private func listenForCommands(location: StorageLocation, service: CommandService) {
        let server = CommandSocketServer(path: location.commandSocketPath) { [weak self] request in
            let response = await service.handle(request)
            if case .added = response { await self?.refresh() }
            return response
        }
        do {
            try server.start()
            commandServer = server
        } catch {
            // The CLI then queues to the inbox, which is still imported.
            commandLineError = "The focuspilot command can’t reach FocusPilot: \(error)"
        }
        Task { [weak self] in
            while let self, let coordinator {
                if (try? await coordinator.importInbox(location.inbox)) ?? 0 > 0 { await refresh() }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    /// Reads Herdr on `HerdrPollSchedule`, which also turns new workspaces
    /// into projects. While Herdr is unreachable it keeps retrying, less
    /// often, without reporting errors. Lists reload only when Herdr's answer
    /// changes.
    private func watchHerdr() {
        Task { [weak self] in
            var schedule = HerdrPollSchedule()
            while let coordinator = self?.coordinator {
                let connection = await coordinator.refreshHerdr()
                guard let self else { return }
                if connection != herdr {
                    herdr = connection
                    await refresh()
                }
                try? await Task.sleep(for: schedule.delay(after: connection))
            }
        }
    }

    // The owner can change the login item in System Settings while the app
    // runs. SwiftUI's onAppear is not guaranteed to fire on each menu open,
    // so re-read the status whenever a menu opens or the app activates.
    private func refreshLoginItem(on name: Notification.Name) {
        Task { [loginItem] in
            for await _ in NotificationCenter.default.notifications(named: name) {
                loginItem.refresh()
            }
        }
    }

    /// True once, on the first launch with no tasks; see `FirstLaunchWelcome`.
    func claimPlanningWindowAtLaunch() async -> Bool {
        guard let coordinator, let hasTasks = try? await coordinator.hasTasks() else { return false }
        return firstLaunch.claimPlanningWindowOpening(hasTasks: hasTasks)
    }

    /// The instant session times are computed for; see `tickWhileTimeIsShown`.
    private(set) var now = Date.now

    var menuBarStatus: MenuBarStatus {
        MenuBarStatus(snapshot: snapshot, now: now, showsTime: menuBarPreferences.showsTime)
    }

    // Advances `now` once a second while a session is active (its time is
    // on screen in the popover and panel), so an idle app is not redrawn
    // every second.
    private func tickWhileTimeIsShown() {
        Task { [weak self] in
            while let self {
                try? await Task.sleep(for: .seconds(1))
                if snapshot.activeSession != nil || menuBarStatus.timeText != nil {
                    now = .now
                }
            }
        }
    }

    /// Takes a snapshot from the coordinator unless a newer one is shown,
    /// since a fetched snapshot can arrive after a streamed one.
    func show(_ latest: FocusSnapshot) {
        now = .now
        guard latest.revision >= snapshot.revision else { return }
        noticeWrapUp(from: snapshot.session, to: latest.session)
        snapshot = latest
        if latest.activeSession == nil || latest.earlyEndAvailableAt != nil {
            isConfirmingEarlyEnd = false
        }
    }

    func refreshTime() {
        now = .now
    }

    func refresh() async {
        guard let coordinator else { return }
        show(await coordinator.snapshot())
        do {
            today = try await coordinator.todayTasks()
            projectTitles = try await coordinator.projectTitles()
            projects = try await coordinator.projects()
            if let shownProject {
                projectItems = try await coordinator.projectTasks(shownProject)
            }
            taskError = nil
        } catch {
            taskError = "Could not load tasks: \(error.localizedDescription)"
        }
    }

    func showProject(_ id: ProjectSummary.ID) async {
        shownProject = id
        await refresh()
    }

    /// Applies the owner's reorder or pin and reloads every list.
    func move(_ id: Int64, to status: TaskStatus, _ placement: TaskPlacement) async {
        guard let coordinator else { return }
        do {
            try await coordinator.moveTask(id, to: status, placement)
        } catch {
            taskError = "Could not move the task: \(error.localizedDescription)"
            return
        }
        await refresh()
    }

    func importHerdrWorkspaces(_ workspaces: [HerdrWorkspace], on server: HerdrServer) async {
        await perform("Could not import the workspaces") {
            try await $0.importHerdrWorkspaces(workspaces, on: server)
        }
    }

    func linkProject(_ projectID: Int64, to workspace: HerdrWorkspace, on server: HerdrServer) async {
        await perform("Could not link the workspace") { try await $0.linkProject(projectID, to: workspace, on: server) }
    }

    func undoHerdrAdd(_ taskID: Int64) async {
        await perform("Could not undo the task") { try await $0.undoHerdrAdd(taskID) }
    }

    func unlinkProject(_ projectID: Int64) async {
        await perform("Could not unlink the workspace") { try await $0.unlinkProject(projectID) }
    }

    private func perform(_ failure: String, _ change: (FocusCoordinator) async throws -> Void) async {
        guard let coordinator else { return }
        do {
            try await change(coordinator)
        } catch {
            taskError = "\(failure): \(error.localizedDescription)"
            return
        }
        await refresh()
    }

    /// Saves the task and reloads Today. Returns false, with `taskError`
    /// set, if nothing was saved.
    func capture(_ newTask: NewTask) async -> Bool {
        guard let coordinator else {
            taskError = startupError
            return false
        }
        do {
            try await coordinator.capture(newTask)
            taskError = nil
        } catch {
            taskError = "Could not save the task: \(error.localizedDescription)"
            return false
        }
        await refresh()
        return true
    }
}
