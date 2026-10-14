import FocusPilotCore
import SwiftUI

/// Lets the owner correct the parsed deadline: its day, whether it has a
/// time, the time, and the time zone. Pickers show the deadline's own zone.
struct DeadlineEditor: View {
    @Binding var deadline: Deadline

    /// Used only when the owner switches a date-only deadline to timed; the
    /// preview shows it immediately so it is never silently assumed.
    private static let defaultTime = (hour: 23, minute: 59)

    var body: some View {
        Form {
            DatePicker("Date", selection: day, displayedComponents: .date)
            Toggle("Include a time", isOn: hasTime)
            if hasTime.wrappedValue {
                DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
            }
            Picker("Time zone", selection: zone) {
                ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0) }
            }
        }
        .environment(\.timeZone, deadline.timeZone)
    }

    private var day: Binding<Date> {
        Binding(
            get: { calendar.date(from: DateComponents(year: deadline.localDate.year, month: deadline.localDate.month, day: deadline.localDate.day))! },
            set: { deadline = deadline.moving(to: LocalDate(containing: $0, in: deadline.timeZone)) }
        )
    }

    private var hasTime: Binding<Bool> {
        Binding(
            get: { deadline.wallClockTime != nil },
            set: { deadline = $0 ? deadline.addingTime(hour: Self.defaultTime.hour, minute: Self.defaultTime.minute) : deadline.removingTime() }
        )
    }

    private var time: Binding<Date> {
        Binding(
            get: {
                guard case .timed(let instant) = deadline.due else { return .now }
                return instant
            },
            set: {
                let parts = calendar.dateComponents([.hour, .minute], from: $0)
                deadline = deadline.addingTime(hour: parts.hour!, minute: parts.minute!)
            }
        )
    }

    private var zone: Binding<String> {
        Binding(
            get: { deadline.timeZone.identifier },
            set: { deadline = deadline.changingTimeZone(to: TimeZone(identifier: $0)!) }
        )
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = deadline.timeZone
        return calendar
    }
}
