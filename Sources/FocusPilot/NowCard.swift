import FocusPilotCore
import SwiftUI

/// The tinted Now card (redesign Main, #71): the deadline, the title, one
/// line of project and next action, and Start focus and Open context; during
/// a session, the time left with Pause and Complete. A session covers
/// projects, not this one task (#56), so it stays when Now changes.
struct NowCard: View {
    let item: TodayItem?
    let showsProject: Bool
    let now: Date
    @Environment(AppModel.self) private var model: AppModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle("Now", color: .palette(.nowLabel))
                Spacer()
                deadline
            }
            VStack(alignment: .leading, spacing: 4) {
                // A space keeps the title's height when Now is empty.
                Text(item?.title ?? " ")
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.22)
                    .foregroundStyle(.palette(.text))
                if let line = item?.nowLine(showsProject: showsProject) {
                    Text(verbatim: line)
                        .font(.system(size: 13))
                        .foregroundStyle(.palette(.secondaryText))
                        .textSelection(.enabled)
                }
            }
            if let model {
                actions(model)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .background(Color.palette(.nowTint), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.palette(.nowBorder)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item == nil ? "Now, no current task" : "Now")
    }

    @ViewBuilder private var deadline: some View {
        if let due = item?.deadline {
            let text = DeadlineText(due)
            Text(text.relative(at: now))
                .font(.system(size: 12))
                .foregroundStyle(due.isOverdue(at: now) ? Color.red : Color.palette(.nowLabel))
                .help(text.inspection)
                .accessibilityLabel(text.spoken(at: now))
        }
    }

    @ViewBuilder
    private func actions(_ model: AppModel) -> some View {
        if let session = model.snapshot.activeSession {
            HStack(spacing: 12) {
                SessionTimeLeft(session: session, now: model.now)
                SessionControls(model: model, showsReturnCue: false)
                    .frame(maxWidth: 240)
                if let item {
                    openContext(item, model)
                }
            }
            .padding(.top, 4)
        } else if let item {
            HStack(spacing: 8) {
                Button { model.requestStartFocus() } label: {
                    Label("Start focus", systemImage: "play.fill")
                }
                .buttonStyle(PaletteButtonStyle(kind: .primary, height: 30, cornerRadius: 7, horizontalPadding: 14))
                .help("Start focus (⌘⏎)")
                .accessibilityHint("Opens Start focus")
                openContext(item, model)
            }
            .padding(.top, 4)
        }
        if let notice = model.contextNotice, model.contextNoticeOnNowCard {
            Text(notice)
                .font(.system(size: 12))
                .foregroundStyle(.palette(.secondaryText))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Opens the task's launch set: with Start focus, resuming takes two clicks.
    private func openContext(_ item: TodayItem, _ model: AppModel) -> some View {
        Button("Open context") { Task { await model.openContext(forTask: item.id, fromNowCard: true) } }
            .buttonStyle(PaletteButtonStyle(height: 30, cornerRadius: 7))
    }
}

private struct SessionTimeLeft: View {
    let session: FocusSession
    let now: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let text = SessionText(session)
        Text(reduceMotion ? text.minutesLeft(at: now) : text.timeLeft(at: now))
            .font(.system(size: 15, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.palette(.text))
            .fixedSize()
            .accessibilityLabel(text.minutesLeft(at: now))
    }
}
