import Foundation

/// Decides whether to open the planning window at launch.
///
/// The window is normally suppressed at launch so that login does not pop it
/// up. A new owner, though, would see only a small menu bar icon and could
/// think nothing happened, so the very first launch with no tasks opens it.
///
/// The "already opened" flag lives in UserDefaults, not the owner database:
/// it is a UI convenience, and losing it only means the window opens once more.
@MainActor
public final class FirstLaunchWelcome {
    private static let openedKey = "didOpenPlanningWindowOnFirstLaunch"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Returns true at most once per defaults domain, and records that it did.
    public func claimPlanningWindowOpening(hasTasks: Bool) -> Bool {
        guard !hasTasks, !defaults.bool(forKey: Self.openedKey) else { return false }
        defaults.set(true, forKey: Self.openedKey)
        return true
    }
}
