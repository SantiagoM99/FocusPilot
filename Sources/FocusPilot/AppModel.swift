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
    private(set) var startupError: String?
    private(set) var taskError: String?
    let loginItem = LoginItemSettings(service: MainAppLoginItem())
    let menuBarPreferences = MenuBarPreferences()
    private let firstLaunch = FirstLaunchWelcome()

    private let coordinator: FocusCoordinator?

    init() {
        do {
            let repository = try TaskRepository(location: .applicationSupport())
            coordinator = FocusCoordinator(repository: repository)
        } catch {
            coordinator = nil
            startupError = "Could not open the database: \(error.localizedDescription)"
        }
        refreshLoginItem(on: NSMenu.didBeginTrackingNotification)
        refreshLoginItem(on: NSApplication.didBecomeActiveNotification)
        tickWhileTimeIsShown()
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

    /// The instant the menu bar time label is computed for.
    private var now = Date.now

    var menuBarStatus: MenuBarStatus {
        MenuBarStatus(snapshot: snapshot, now: now, showsTime: menuBarPreferences.showsTime)
    }

    // Advances `now` once a second, but only while a time label is visible,
    // so an idle menu bar item is not redrawn every second.
    private func tickWhileTimeIsShown() {
        Task { [weak self] in
            while let self {
                try? await Task.sleep(for: .seconds(1))
                if menuBarStatus.timeText != nil {
                    now = .now
                }
            }
        }
    }

    func refresh() async {
        guard let coordinator else { return }
        snapshot = await coordinator.snapshot()
        do {
            today = try await coordinator.todayTasks()
            projectTitles = try await coordinator.projectTitles()
            taskError = nil
        } catch {
            taskError = "Could not load tasks: \(error.localizedDescription)"
        }
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
