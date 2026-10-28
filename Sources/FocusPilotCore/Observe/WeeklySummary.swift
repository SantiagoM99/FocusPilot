import Foundation

/// The last seven days of pilot events (VALIDATION_PLAN.md, measures):
/// sessions, resume time and distraction visits, comparable between the
/// baseline week and the pilot.
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

    public init(events: [PilotEvent], now: Date) {
        let start = now.addingTimeInterval(-Self.period)
        var resumeTimes: [TimeInterval] = []
        for event in events where event.at >= start && event.at <= now {
            switch event.kind {
            case .sessionStarted: sessionsStarted += 1
            case .sessionEnded: sessionsEnded += 1
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
            }
        }
        medianResume = Self.median(resumeTimes)
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
        ]
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
