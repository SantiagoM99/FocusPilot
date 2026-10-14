/// Whether the system will launch FocusPilot when the owner logs in.
public enum LoginItemStatus: Sendable {
    case enabled
    case disabled
    /// Registered, but the owner must allow it in System Settings › General › Login Items.
    case requiresApproval
    /// The system cannot find the app to register, e.g. when running the bare
    /// executable outside `FocusPilot.app`.
    case unavailable
}

/// The system's login-item registry. `MainAppLoginItem` is the real one;
/// tests substitute a fake.
@MainActor
public protocol LoginItemService: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}
