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
        /// What VoiceOver reads for the value: units spelled out, commas for
        /// middle dots (as #66 did for In flight).
        public var spoken: String

        public init(label: String, value: String, spoken: String? = nil) {
            self.label = label
            self.value = value
            self.spoken = spoken ?? value.replacing(" · ", with: ", ")
        }
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
    /// The length of those sessions inside the seven days.
    public var focusTime: TimeInterval = 0
    public var backIntoThreadTimes: [TimeInterval] = []
    public var agentWaits: [TimeInterval] = []

    public init(events: [PilotEvent], now: Date) {
        let start = now.addingTimeInterval(-Self.period)
        var resumeTimes: [TimeInterval] = []
        var touches: [UUID: Int] = [:]
        /// Ended sessions, and whether each began inside the seven days.
        var ended: [UUID: Bool] = [:]
        for event in events where event.at >= start && event.at <= now {
            switch event.kind {
            case .sessionStarted: sessionsStarted += 1
            case .sessionEnded:
                sessionsEnded += 1
                // A session that began before the seven days counts only its part inside them.
                if let id = event.sessionID, ended[id] == nil {
                    let began = event.at.addingTimeInterval(-(event.duration ?? 0))
                    ended[id] = began >= start
                    focusTime += event.at.timeIntervalSince(max(began, start))
                }
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
        // The first task a session took up is not a switch; for a session
        // that began before the seven days, it was taken up outside them.
        switches = ended.reduce(0) { $0 + max(0, (touches[$1.key] ?? 0) - ($1.value ? 1 : 0)) }
    }

    public var lines: [Line] {
        [
            Line(label: "Focus sessions",
                 value: sessionsStarted == 0 ? "None yet" : "\(sessionsStarted) started · \(sessionsEnded) ended"),
            metric("Resume time", medianResume.map { median in { units in
                "median \(units.duration(median))\(units.dot)\(resumes) resume\(resumes == 1 ? "" : "s")"
            } }, none: "No resumes yet"),
            metric("Distraction visits", distractionVisits == 0 ? nil : { units in
                "\(distractionVisits)\(units.dot)\(units.minutes(distractionTime))\(units.dot)\(distractionVisitsInSessions) during sessions"
            }, none: "None"),
            Line(label: "Blocked visits", value: blockedVisits == 0 ? "None"
                 : "\(blockedVisits) · \(blockedVisitsInSessions) during sessions"),
            Line(label: "Exceptions", value: "\(exceptionsGranted) granted"),
            metric("Switches", focusTime <= 0 ? nil : { units in
                "\(Self.rate(Double(switches) / (focusTime / 3600))) per hour\(units.dot)\(switches) in \(units.hours(focusTime))"
            }, none: "No sessions ended yet"),
            metric("Back into a thread", Self.median(backIntoThreadTimes).map { median in { units in
                let count = backIntoThreadTimes.count
                return "median \(units.duration(median))\(units.dot)\(count) switch\(count == 1 ? "" : "es")"
            } }, none: "No switches yet"),
            metric("Agents waiting for you", Self.median(agentWaits).map { median in { units in
                let count = agentWaits.count
                return "median \(units.minutes(median))\(units.dot)longest \(units.minutes(agentWaits.max() ?? median))\(units.dot)"
                    + "\(count) \(count == 1 ? "result or request" : "results and requests")"
            } }, none: "None yet"),
        ]
    }

    /// A line written once for the screen and once for VoiceOver.
    private func metric(_ label: String, _ text: ((Units) -> String)?, none: String) -> Line {
        guard let text else { return Line(label: label, value: none) }
        return Line(label: label, value: text(.shown), spoken: text(.spoken))
    }

    /// "44 s" on screen, "44 seconds" for VoiceOver.
    private enum Units {
        case shown, spoken

        var dot: String { self == .shown ? " · " : ", " }

        func duration(_ seconds: TimeInterval) -> String {
            let total = Int(seconds.rounded())
            return join(minutes: total / 60, seconds: total % 60)
        }

        func minutes(_ seconds: TimeInterval) -> String {
            let minutes = Int((seconds / 60).rounded())
            return self == .shown ? "\(minutes) min" : Self.count(minutes, "minute")
        }

        func hours(_ seconds: TimeInterval) -> String {
            let minutes = Int((seconds / 60).rounded())
            let (hours, rest) = (minutes / 60, minutes % 60)
            if hours == 0 { return self == .shown ? "\(rest) min" : Self.count(rest, "minute") }
            let whole = self == .shown ? "\(hours) h" : Self.count(hours, "hour")
            guard rest > 0 else { return whole }
            return whole + " " + (self == .shown ? "\(rest) min" : Self.count(rest, "minute"))
        }

        private func join(minutes: Int, seconds: Int) -> String {
            if self == .shown {
                return minutes == 0 ? "\(seconds) s" : "\(minutes) min" + (seconds == 0 ? "" : " \(seconds) s")
            }
            if minutes == 0 { return Self.count(seconds, "second") }
            return Self.count(minutes, "minute") + (seconds == 0 ? "" : " " + Self.count(seconds, "second"))
        }

        private static func count(_ value: Int, _ unit: String) -> String {
            "\(value) \(unit)\(value == 1 ? "" : "s")"
        }
    }

    /// "1.3", one decimal.
    private static func rate(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US")))
    }

    private static func median(_ values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
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
