import AppKit
import FocusPilotCore
import Observation

/// Builds the long-lived core objects once and exposes what the views show.
@MainActor
@Observable
final class AppModel {
    private(set) var snapshot = FocusSnapshot()
    private(set) var startupError: String?
    let loginItem = LoginItemSettings(service: MainAppLoginItem())

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

    func refresh() async {
        guard let coordinator else { return }
        snapshot = await coordinator.snapshot()
    }
}
