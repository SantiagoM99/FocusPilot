import FocusPilotCore
import SwiftUI

/// How the deadline phrase was read, before anything is saved: the date
/// and time, with its zone and source on hover, and a warning if it is
/// already in the past.
struct DeadlinePreview: View {
    let deadlineText: String?
    let deadline: Deadline?

    var body: some View {
        if let deadline {
            let text = DeadlineText(deadline)
            // Re-evaluated every minute, so a deadline that passes while the
            // sheet is open gains the warning.
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.dayAndTime(at: context.date))
                        .foregroundStyle(.palette(.text))
                        .help(text.inspection + " · " + text.source)
                    if let warning = text.pastWarning(at: context.date) {
                        Text(warning)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        } else if let deadlineText {
            Label(DeadlineParser.hint(for: deadlineText), systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.palette(.secondaryText))
        } else {
            Text("None")
                .foregroundStyle(.palette(.secondaryText))
        }
    }
}
