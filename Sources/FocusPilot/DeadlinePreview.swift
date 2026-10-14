import FocusPilotCore
import SwiftUI

/// Shows how the typed deadline was read, before anything is saved: exact
/// date (and time), whether it is date-only or timed, its time zone, and the
/// text it came from.
struct DeadlinePreview: View {
    let typedText: String
    let deadline: Deadline?

    var body: some View {
        if let deadline {
            let text = DeadlineText(deadline)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.exact)
                        .font(.body.weight(.semibold))
                    Text(text.kind)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(text.source)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
            .accessibilityElement(children: .combine)
        } else if typedText.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("Optional. For example “fri 23:59” or “Oct 20”.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        } else {
            Label("Could not read this deadline. Try “fri 23:59”, “Oct 20” or “2026-10-20”.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
