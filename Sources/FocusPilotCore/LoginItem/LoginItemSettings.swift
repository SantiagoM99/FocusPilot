import Observation

/// Backs the "Open at Login" toggle.
///
/// After every change it re-reads the status from the system instead of
/// trusting the request, so the toggle shows what will actually happen at
/// the next login even when registration fails or awaits approval.
@MainActor
@Observable
public final class LoginItemSettings {
    public private(set) var status: LoginItemStatus
    public private(set) var errorMessage: String?

    private let service: any LoginItemService

    public init(service: any LoginItemService) {
        self.service = service
        status = service.status
    }

    public var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    public var needsApproval: Bool {
        status == .requiresApproval
    }

    public func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    public func refresh() {
        status = service.status
    }

    public func openSystemSettings() {
        service.openSystemSettings()
    }
}
