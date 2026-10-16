import FocusPilotCore
import SwiftUI

/// A Next or Later row: drag handle, title, then project and deadline.
struct TaskRow: View {
    let item: TodayItem
    let showsProject: Bool
    let now: Date

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                TaskMeta(item: item, showsProject: showsProject, now: now)
                    .font(.callout)
            }
        }
        .padding(.vertical, 4)
    }
}

/// "NLP report · Due Fri 23:59", the project left out inside a project.
/// The deadline is red when overdue; hovering or VoiceOver gives the exact
/// date, time and time zone.
struct TaskMeta: View {
    let item: TodayItem
    let showsProject: Bool
    let now: Date

    var body: some View {
        let deadline = item.deadline.map(DeadlineText.init)
        let label = deadline?.relative(at: now) ?? "No deadline"
        let isOverdue = item.deadline?.isOverdue(at: now) == true
        let project = showsProject ? item.projectTitle.map { $0 + " · " } ?? "" : ""
        (Text(project).foregroundStyle(Color.secondary)
            + Text(label).foregroundStyle(isOverdue ? Color.red : Color.secondary))
            .help(deadline?.inspection ?? "")
            .accessibilityLabel(project + label + (deadline.map { ", " + $0.inspection } ?? ""))
    }
}
