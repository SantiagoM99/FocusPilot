import Foundation

/// The last seven days of pilot events (VALIDATION_PLAN.md, measures):
/// sessions, resume time and distraction visits, comparable between the
/// baseline week and the pilot; and parallel work (decision 0004, #58):
/// switches per focus hour, time to get back into a thread, and how long
/// agents waited for the owner.
public struct WeeklySummary: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public var label: String
        public var value: String
    }

    public static let period: TimeInterval = 7 * 86400

    public var sessionsStarted = 0
    public var sessionsEnded = 0
    public var resumes = 0
    public var medianResume: TimeInterval?
    public var distractionVisits = 0
    public var distractionVisitsInSessions = 0
    public var distractionTime: TimeInterval = 0
    public var exceptionsGranted = 0
    /// While blocking: blocked apps hidden as they came forward.
    public var blockedVisits = 0
    public var blockedVisitsInSessions = 0
    /// Changes of Now inside sessions that ended this week; the first task a
    /// session takes up is not a switch.
    public var switches = 0
    /// The length of those sessions.
    public var focusTime: TimeInterval = 0
    public var backIntoThreadTimes: [TimeInterval] = []
    public var agentWaits: [TimeInterval] = []

    public init(events: [PilotEvent], now: Date) {
        let start = now.addingTimeInterval(-Self.period)
        var resumeTimes: [TimeInterval] = []
        var touches: [UUID: Int] = [:]
        var ended: Set<UUID> = []
        for event in events where event.at >= start && event.at <= now {
            switch event.kind {
            case .sessionStarted: sessionsStarted += 1
            case .sessionEnded:
                sessionsEnded += 1
                if let id = event.sessionID, ended.insert(id).inserted { focusTime += event.duration ?? 0 }
            case .resume:
                resumes += 1
                resumeTimes.append(event.duration ?? 0)
            case .distractionVisit:
                distractionVisits += 1
                if event.sessionID != nil { distractionVisitsInSessions += 1 }
                distractionTime += event.duration ?? 0
            case .exceptionGranted: exceptionsGranted += 1
            case .blockedVisit:
                blockedVisits += 1
                if event.sessionID != nil { blockedVisitsInSessions += 1 }
            case .taskTouched:
                if let id = event.sessionID { touches[id, default: 0] += 1 }
            case .backIntoThread: backIntoThreadTimes.append(event.duration ?? 0)
            case .agentWait: agentWaits.append(event.duration ?? 0)
            }
        }
        medianResume = Self.median(resumeTimes)
        switches = ended.reduce(0) { $0 + max(0, (touches[$1] ?? 0) - 1) }
    }

    public var lines: [Line] {
        [
            Line(label: "Focus sessions",
                 value: sessionsStarted == 0 ? "None yet" : "\(sessionsStarted) started · \(sessionsEnded) ended"),
            Line(label: "Resume time", value: medianResume.map {
                "median \(Self.duration($0)) · \(resumes) resume\(resumes == 1 ? "" : "s")"
            } ?? "No resumes yet"),
            Line(label: "Distraction visits", value: distractionVisits == 0 ? "None"
                 : "\(distractionVisits) · \(Self.minutes(distractionTime)) · \(distractionVisitsInSessions) during sessions"),
            Line(label: "Blocked visits", value: blockedVisits == 0 ? "None"
                 : "\(blockedVisits) · \(blockedVisitsInSessions) during sessions"),
            Line(label: "Exceptions", value: "\(exceptionsGranted) granted"),
            Line(label: "Switches", value: focusTime <= 0 ? "No sessions ended yet"
                 : "\(Self.rate(Double(switches) / (focusTime / 3600))) per hour · \(switches) in \(Self.hours(focusTime))"),
            Line(label: "Back into a thread", value: Self.median(backIntoThreadTimes).map {
                "median \(Self.duration($0)) · \(backIntoThreadTimes.count) switch\(backIntoThreadTimes.count == 1 ? "" : "es")"
            } ?? "No switches yet"),
            Line(label: "Agents waiting for you", value: Self.median(agentWaits).map { median in
                let count = agentWaits.count
                return "median \(Self.minutes(median)) · longest \(Self.minutes(agentWaits.max() ?? median)) · "
                    + "\(count) \(count == 1 ? "result or request" : "results and requests")"
            } ?? "None yet"),
        ]
    }

    /// "1.3", one decimal.
    private static func rate(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US")))
    }

    /// "3 h", "7 h 40 min", "40 min".
    private static func hours(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    private static func median(_ values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// "12 s", "2 min 30 s".
    private static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return total < 60 ? "\(total) s" : "\(total / 60) min" + (total % 60 == 0 ? "" : " \(total % 60) s")
    }

    private static func minutes(_ seconds: TimeInterval) -> String {
        "\(Int((seconds / 60).rounded())) min"
    }
}

/// Where the baseline week stands (design 12): "Baseline week · day 4 of 7".
public struct BaselineWeek: Equatable, Sendable {
    public static let length = 7

    /// 1 on the day observing started, by calendar day.
    public var day: Int
    private var since: String

    public init(since: Date, now: Date, calendar: Calendar = .current) {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: since),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        day = max(1, days + 1)
        let format = Date.FormatStyle(date: .omitted, time: .omitted, locale: Locale(identifier: "en_GB"),
                                      calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.abbreviated).day().month(.abbreviated)
        self.since = since.formatted(format).replacingOccurrences(of: ",", with: "")
    }

    public var isDone: Bool { day > Self.length }

    public var menuLine: String {
        isDone ? "Observing · day \(day)" : "Baseline week · day \(day) of \(Self.length)"
    }

    public var observedLine: String {
        isDone ? "\(day) days · since \(since) · the baseline week is done"
            : "\(day) of \(Self.length) days · since \(since)"
    }
}
