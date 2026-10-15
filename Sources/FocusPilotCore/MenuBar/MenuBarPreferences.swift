import Foundation
import Observation

/// Owner choices about the menu bar item. Stored in UserDefaults: they are
/// display conveniences, not owner data the database must keep.
@MainActor
@Observable
public final class MenuBarPreferences {
    private static let showsTimeKey = "menuBarShowsTime"

    private let defaults: UserDefaults

    /// Show the time left next to the glyph while a session is active. Off by
    /// default, so the menu bar item stays a single icon (the logo design
    /// keeps it narrow enough not to be hidden behind the notch).
    public var showsTime: Bool {
        didSet { defaults.set(showsTime, forKey: Self.showsTimeKey) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showsTime = defaults.bool(forKey: Self.showsTimeKey)
    }
}
