import FocusPilotCore
import SwiftUI

/// A 44 pt Next or Later row: title, project and short deadline. Selected
/// rows are tinted by the list. A task added with the focuspilot CLI says
/// "from Herdr" and has an Undo button.
struct TaskRow: View {
    let item: TodayItem
    let showsProject: Bool
    let now: Date
    let isSelected: Bool
    var undo: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Text(item.title)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundStyle(.palette(item.status == .later ? .footerText : .text))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let undo {
                Button("Undo", action: undo)
                    .buttonStyle(.link)
                    .controlSize(.small)
                    .help("Remove this task added from Herdr")
            }
            if !source.isEmpty {
                Text(verbatim: source)
                    .font(.system(size: 12))
                    .foregroundStyle(.palette(.secondaryText))
                    .lineLimit(1)
            }
            deadline
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        // One item for VoiceOver: "PhD shortlist, Applications, due Tuesday
        // 20 October"; Undo stays reachable as an action.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.spokenLabel(showsProject: showsProject, at: now))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityActions {
            if let undo { Button("Undo add from Herdr", action: undo) }
        }
    }

    /// "Applications", "Applications · from Herdr", or "" inside a project.
    private var source: String {
        [showsProject ? item.projectTitle : nil, item.isFromHerdr ? "from Herdr" : nil]
            .compactMap(\.self).joined(separator: " · ")
    }

    private var deadline: some View {
        let text = item.deadline.map(DeadlineText.init)
        return Text(text?.short(at: now) ?? "")
            .font(.system(size: 12))
            .foregroundStyle(item.deadline?.isOverdue(at: now) == true ? Color.red : Color.palette(.secondaryText))
            .fixedSize()
            .frame(minWidth: 64, alignment: .trailing)
            .help(text?.inspection ?? "")
    }
}
