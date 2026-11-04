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

    public init(text: String, tone: Tone) {
        self.text = text
        self.tone = tone
    }

    public init(protection: BrowserProtection, observing: Bool) {
        guard !observing else {
            self.init(text: "Observing · nothing blocked", tone: .unknown)
            return
        }
        let tone: Tone = switch protection.level {
        case .protected: .green
        case .syncing, .degraded: .amber
        case .unknown: .unknown
        }
        self.init(text: protection.footer, tone: tone)
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
