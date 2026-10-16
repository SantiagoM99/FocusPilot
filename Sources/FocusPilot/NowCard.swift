import FocusPilotCore
import SwiftUI

/// The pinned Now task and its next action, or an empty state when the
/// owner has not chosen one.
struct NowCard: View {
    let item: TodayItem?
    let caption: String?
    let showsProject: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Label("Now", systemImage: "pin.fill")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                if let caption {
                    Text("· " + caption)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            if let item {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.title2.weight(.semibold))
                    TaskMeta(item: item, showsProject: showsProject, now: now)
                }
                if let nextAction = item.nextAction {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next action")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(nextAction)
                            .textSelection(.enabled)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("No current task")
                        .font(.title3.weight(.semibold))
                    Text("Pick one from Next and press ⌘1, or capture a new one.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
        .accessibilityElement(children: .combine)
    }
}
