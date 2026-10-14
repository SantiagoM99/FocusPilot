import FocusPilotCore
import SwiftUI

/// Saved tasks in capture order. Now/Next/Later and manual ordering come
/// with the planning window ticket.
struct TodayList: View {
    let items: [TodayItem]

    var body: some View {
        // Relative labels ("Due today 17:00", "Overdue …") change with time.
        TimelineView(.everyMinute) { context in
            List(items) { item in
                TaskRow(item: item, now: context.date)
            }
        }
    }
}

private struct TaskRow: View {
    let item: TodayItem
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(.headline)
            HStack(spacing: 4) {
                if let projectTitle = item.projectTitle {
                    Text(projectTitle)
                    Text("·")
                }
                DeadlineLabel(deadline: item.deadline, now: now)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            if let nextAction = item.nextAction {
                Text(nextAction)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Relative deadline ("Due Fri 23:59"), red when overdue. Hovering or
/// VoiceOver gives the exact date, time and time zone.
private struct DeadlineLabel: View {
    let deadline: Deadline?
    let now: Date

    var body: some View {
        if let deadline {
            let text = DeadlineText(deadline)
            Text(text.relative(at: now))
                .foregroundStyle(deadline.isOverdue(at: now) ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .help(text.inspection)
                .accessibilityLabel("\(text.relative(at: now)), \(text.inspection)")
        } else {
            Text("No deadline")
        }
    }
}
