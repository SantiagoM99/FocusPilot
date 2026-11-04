import Foundation

/// The planning window sidebar's footer (#70): one line with the real
/// browser protection state, or that observe-only blocks nothing.
public struct SidebarFooter: Equatable, Sendable {
    public enum Tone: Sendable {
        case green, amber
        /// A hollow grey dot: not known yet, or nothing is blocked.
        case unknown
    }

    public var text: String
    public var tone: Tone
    /// The full status line, shown on hover.
    public var help: String

    public init(text: String, tone: Tone, help: String) {
        self.text = text
        self.tone = tone
        self.help = help
    }

    public init(protection: BrowserProtection, observing: Bool) {
        guard !observing else {
            self.init(text: "Observing · nothing blocked", tone: .unknown, help: "Observing · nothing blocked")
            return
        }
        let tone: Tone = switch protection.level {
        case .protected: .green
        case .syncing, .degraded: .amber
        case .unknown: .unknown
        }
        self.init(text: protection.footer, tone: tone, help: protection.line)
    }
}

/// The planning window's pages in sidebar order (#70).
public enum PlanningPage: CaseIterable, Hashable, Sendable {
    case today, inFlight, projects, review, settings

    /// The page `offset` rows away, for the arrow keys; it stops at the ends.
    public func moved(by offset: Int) -> PlanningPage {
        let all = Self.allCases
        let index = all.firstIndex(of: self)! + offset
        return all[min(max(index, 0), all.count - 1)]
    }
}

/// The grey count pills on In flight and Review queue (#70).
public enum SidebarBadge {
    /// Nil at zero, so the pill hides.
    public static func text(_ count: Int) -> String? {
        count <= 0 ? nil : count > 99 ? "99+" : "\(count)"
    }
}

/// The planning window header (#70): the page title and, on Today, the date.
public enum PageHeader {
    /// "Tuesday 3 November".
    public static func todayDate(_ date: Date, calendar: Calendar = .current) -> String {
        let format = Date.FormatStyle(date: .omitted, time: .omitted, locale: Locale(identifier: "en_GB"),
                                      calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.wide).day().month(.wide)
        return date.formatted(format).replacingOccurrences(of: ",", with: "")
    }
}
