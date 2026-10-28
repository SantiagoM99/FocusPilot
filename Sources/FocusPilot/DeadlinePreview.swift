import FocusPilotCore
import SwiftUI

/// Shows how the deadline phrase was read, before anything is saved: exact
/// date (and time), whether it is date-only or timed, its time zone, the
/// text it came from, and a warning if it is already in the past.
struct DeadlinePreview: View {
    let deadlineText: String?
    let deadline: Deadline?

    var body: some View {
        if let deadline {
            let text = DeadlineText(deadline)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.exact)
                        .font(.body.weight(.semibold))
                    Text(text.kind)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(text.source)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                    // Re-evaluated every minute, so a deadline that passes
                    // while the sheet is open gains the warning.
                    TimelineView(.everyMinute) { context in
                        if let warning = text.pastWarning(at: context.date) {
                            Text(warning)
                                .font(.callout)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .accessibilityElement(children: .combine)
        } else if let deadlineText {
            Label(DeadlineParser.hint(for: deadlineText), systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            Text("None — type it above or click to choose")
                .foregroundStyle(.secondary)
        }
    }
}
