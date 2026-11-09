import Foundation
import Observation

/// What Start focus begins with (Settings › Blocking › Sessions). Kept in
/// UserDefaults, like the menu bar preferences.
@MainActor
@Observable
public final class SessionPreferences {
    /// The lengths offered, in the board's order. The first is the default.
    public static let lengths = [50, 25, 90]

    private static let minutesKey = "defaultSessionMinutes"
    private static let strictKey = "strictByDefault"

    private let defaults: UserDefaults

    public var defaultMinutes: Int {
        didSet { defaults.set(defaultMinutes, forKey: Self.minutesKey) }
    }

    public var strictByDefault: Bool {
        didSet { defaults.set(strictByDefault, forKey: Self.strictKey) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.integer(forKey: Self.minutesKey)
        defaultMinutes = Self.lengths.contains(stored) ? stored : Self.lengths[0]
        strictByDefault = defaults.bool(forKey: Self.strictKey)
    }
}
