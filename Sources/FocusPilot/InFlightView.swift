import FocusPilotCore
import SwiftUI

/// In flight (redesign, InFlight board): three flat sections, and the
/// selected row in the inspector. Switch asks first; nothing here switches
/// on its own, and agent text is shown verbatim.
struct InFlightView: View {
    let model: AppModel

    var body: some View {
        let board = model.inFlightBoard
        InFlightList(model: model, sections: [
            .init(title: "WAITING ON YOU", titleColor: .amberText, dot: .amber, rows: board.waitingOnYou),
            .init(title: "RUNNING", titleColor: .secondaryText, dot: .accent, rows: board.running),
            .init(title: "WAITING", titleColor: .secondaryText, dot: .idleDot, rows: board.waiting),
        ])
    }
}

/// One item that needs the owner: what happened, where, how long it has
/// waited (quietly marked after 30 minutes), Switch and a way to clear it.
struct AttentionRow: View {
    let model: AppModel
    let item: AttentionItem
    var compact = false

    var body: some View {
        if let report = item.report {
            ReportRow(model: model, item: item, report: report, compact: compact)
        } else {
            taskRow
        }
    }

    private var taskRow: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: compact ? [item.headline, item.projectTitle].compactMap(\.self).joined(separator: " · ")
                         : item.headline)
                        .fontWeight(.medium)
                        .lineLimit(compact ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                    if !compact {
                        Text(verbatim: item.place)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    WaitedText(item: item, now: model.attentionTime)
                }
            }
            // One item for VoiceOver, without the middle dots; the buttons
            // stay separate so each can be reached and pressed.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AttentionText.spoken(item, at: model.attentionTime))
            Spacer(minLength: 8)
            if !compact {
                Button(dismissTitle) { Task { await dismiss() } }
                    .buttonStyle(.borderless)
                    .accessibilityHint(item.kind == .check ? "Removes this check" : "Removes this item from Needs you")
            }
            if let request = SwitchRequest(item) {
                Button("Switch") { model.requestSwitch(request) }
                    .help("Asks where you left off, then makes this task Now\(item.linkID == nil ? "" : " and opens the agent")")
                    .accessibilityHint("Switch to \(item.taskTitle)")
            }
        }
        .padding(.horizontal, compact ? 0 : 14)
        .padding(.vertical, compact ? 4 : 10)
    }

    private var symbol: String {
        switch item.kind {
        case .approval: "hand.raised.fill"
        case .finished: "checkmark.circle.fill"
        case .check: "clock.fill"
        case .report: "text.bubble.fill"
        }
    }

    private var color: Color {
        switch item.kind {
        case .approval: .orange
        case .finished: .green
        case .check: .blue
        case .report: .purple
        }
    }

    private var dismissTitle: String {
        item.kind == .check ? "Dismiss" : "Mark reviewed"
    }

    private func dismiss() async {
        switch item.id {
        case .review(let id): await model.markReviewed(id)
        case .check(let taskID): await model.dismissCheck(taskID)
        case .report(let id): await model.dismissReport(id)
        }
    }
}

/// "Waiting 12 min"; after 30 minutes the same words in orange with a
/// small clock. No sound and no motion.
struct WaitedText: View {
    let item: AttentionItem
    let now: Date

    var body: some View {
        let text = AttentionText.waited(item, at: now)
        if item.needsAlert(at: now) {
            Label(text, systemImage: "clock")
                .font(.callout)
                .foregroundStyle(.orange)
        } else {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
