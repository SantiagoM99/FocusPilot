import FocusPilotCore
import SwiftUI

/// The pinned Now task and its next action, or an empty state when the
/// owner has not chosen one.
struct NowCard: View {
    let item: TodayItem?
    let caption: String?
    let showsProject: Bool
    let now: Date
    @Environment(AppModel.self) private var model: AppModel?

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
                        Text(item.wrapUp.flatMap { nextAction == $0.returnCue ? $0.nextActionCaption : nil } ?? "Next action")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(nextAction)
                            .textSelection(.enabled)
                        if let remaining = item.wrapUp?.remainingWork {
                            Text("\(Text("Remains: ").foregroundStyle(.secondary))\(remaining)")
                                .font(.callout)
                                .padding(.top, 2)
                        }
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
            if let model {
                session(model)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
        .accessibilityElement(children: .contain)
    }

    /// Start focus, or the session already running. A session covers
    /// projects, not this one task (#56), so it stays when Now changes.
    @ViewBuilder
    private func session(_ model: AppModel) -> some View {
        if let session = model.snapshot.activeSession {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    SessionHeader(session: session, now: model.now, timeFont: .title3.weight(.semibold))
                    Text(SessionText.covers(session.scope))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let note = model.outsideNote {
                        Text(note)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                SessionControls(model: model, showsReturnCue: false)
                if let item {
                    openContext(item, model)
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: 360)
        } else {
            HStack {
                Button { model.requestStartFocus() } label: {
                    Label("Start focus", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .help("Start focus (⌘⏎)")
                .accessibilityHint("Opens Start focus")
                if let item {
                    openContext(item, model)
                }
            }
            .controlSize(.large)
        }
        if let notice = model.contextNotice, model.contextNoticeOnNowCard {
            Text(notice)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Opens the task's launch set: with Start focus, resuming takes two clicks.
    private func openContext(_ item: TodayItem, _ model: AppModel) -> some View {
        Button { Task { await model.openContext(forTask: item.id, fromNowCard: true) } } label: {
            Label("Open context", systemImage: "arrow.up.forward.app")
        }
        .help("Opens the task’s ticked resources, checking each one first. Nothing is created.")
    }
}
