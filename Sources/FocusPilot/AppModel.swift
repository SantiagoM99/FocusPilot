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
    }

    func refresh() async {
        guard let coordinator else { return }
        snapshot = await coordinator.snapshot()
    }
}
