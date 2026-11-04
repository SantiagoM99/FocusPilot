import FocusPilotCore
import SwiftUI

/// Decision 0004: what needs the owner now, at the top, then every thread
/// that moves without them, grouped by project and collapsed. Nothing here
/// switches on its own; Switch asks first, and agent text is shown verbatim.
struct InFlightView: View {
    let model: AppModel
    @State private var expanded: Set<Int64?> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section("Needs you") {
                    if model.attention.isEmpty {
                        note("Nothing needs you right now. Agent results, approval requests and checks you scheduled appear here.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(model.attention.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { Divider() }
                                AttentionRow(model: model, item: item)
                            }
                        }
                        .card()
                    }
                }
                section("In flight") {
                    if model.inFlight.isEmpty {
                        note("Nothing in flight. Link an agent to a task, or mark a task as waiting from its menu.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(model.inFlight.enumerated()), id: \.element.id) { index, project in
                                if index > 0 { Divider() }
                                DisclosureGroup(isExpanded: isExpanded(project.id)) {
                                    VStack(spacing: 0) {
                                        ForEach(project.threads) { ThreadRow(model: model, thread: $0) }
                                    }
                                } label: {
                                    Text(project.summary)
                                        .fontWeight(.medium)
                                        .accessibilityLabel(project.summary.replacing(" · ", with: ", "))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                            }
                        }
                        .card()
                    }
                }
                if let notice = model.agentNotice {
                    Label(notice, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    private func isExpanded(_ id: Int64?) -> Binding<Bool> {
        Binding(get: { expanded.contains(id) },
                set: { if $0 { expanded.insert(id) } else { expanded.remove(id) } })
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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

/// One thread inside a project: its state, the agent or what it waits on,
/// the task, and Switch.
private struct ThreadRow: View {
    let model: AppModel
    let thread: InFlightThread

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                StatusDot(title: stateTitle, color: stateColor, filled: thread.state != .waiting)
                    .frame(width: 96, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: thread.label)
                        .lineLimit(1)
                    Text(verbatim: detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([stateTitle, thread.label, detail.replacing(" · ", with: ", ")].joined(separator: ", "))
            Spacer(minLength: 8)
            if case .waiting(let taskID) = thread.id {
                Button("Stop waiting") { Task { await model.stopWaiting(taskID) } }
                    .buttonStyle(.borderless)
                    .accessibilityHint("Takes \(thread.taskTitle) out of In flight")
            }
            Button("Switch") { model.requestSwitch(SwitchRequest(thread)) }
                .accessibilityHint("Switch to \(thread.taskTitle)")
        }
        .padding(.vertical, 6)
        .padding(.leading, 18)
    }

    private var stateTitle: String {
        switch thread.state {
        case .working: "Working"
        case .needsYou: "Needs you"
        case .finished: "Finished"
        case .waiting: "Waiting"
        }
    }

    private var stateColor: Color {
        switch thread.state {
        case .working: .blue
        case .needsYou: .orange
        case .finished: .green
        case .waiting: .secondary
        }
    }

    /// "Run ablation · since 10:15", or "Send the draft · check at 15:00".
    private var detail: String {
        let time = { (date: Date) in date.formatted(date: .omitted, time: .shortened) }
        if thread.state == .waiting, let checkAt = thread.checkAt {
            return "\(thread.taskTitle) · check at \(time(checkAt))"
        }
        return "\(thread.taskTitle) · since \(time(thread.since))"
    }
}

private extension View {
    func card() -> some View {
        background(.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
    }
}
