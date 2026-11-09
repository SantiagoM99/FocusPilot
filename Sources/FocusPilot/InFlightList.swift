import FocusPilotCore
import SwiftUI

/// The list and inspector In flight and the Review queue share.
struct InFlightList: View {
    struct Section: Identifiable {
        var title: String?
        var titleColor: Palette.Token
        var dot: Palette.Token
        var rows: [InFlightRow]
        var id: String { title ?? "" }
    }

    let model: AppModel
    let sections: [Section]
    @State private var selection: InFlightRow.ID?

    private var rows: [InFlightRow] { sections.flatMap(\.rows) }
    private var selected: InFlightRow? { InFlightRow.selected(selection, in: rows) }

    var body: some View {
        HStack(spacing: 0) {
            list
                .frame(minWidth: 300, maxWidth: .infinity)
            if let selected {
                InFlightInspector(model: model, row: selected)
                    .id(selected.id)
                    .frame(minWidth: 260, idealWidth: 340, maxWidth: 340, maxHeight: .infinity)
                    .background(Color.palette(.inspector))
                    .overlay(alignment: .leading) { Rectangle().fill(Color.palette(.separator)).frame(width: 1) }
            }
        }
    }

    private var list: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    ForEach(sections.filter { !$0.rows.isEmpty }) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            if let title = section.title {
                                Text(title)
                                    .font(.system(size: 11, weight: .bold))
                                    .tracking(0.88)
                                    .foregroundStyle(.palette(section.titleColor))
                                    .padding(.horizontal, 6)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            VStack(spacing: 0) {
                                ForEach(section.rows) { row in
                                    InFlightRowView(model: model, row: row, dot: section.dot,
                                                    isSelected: row.id == selected?.id) { selection = row.id }
                                        .id(row.id)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
            }
            .focusable()
            .focusEffectDisabled()
            .onMoveCommand { direction in
                guard let next = neighbor(direction) else { return }
                selection = next
                reader.scrollTo(next)
            }
            .onChange(of: selected?.id) { model.agentNotice = nil }
        }
    }

    private func neighbor(_ direction: MoveCommandDirection) -> InFlightRow.ID? {
        guard let selected, let index = rows.firstIndex(where: { $0.id == selected.id }) else { return nil }
        let target = switch direction {
        case .up: index - 1
        case .down: index + 1
        default: index
        }
        return rows.indices.contains(target) ? rows[target].id : nil
    }
}

/// Status dot, task title, one detail line and the row's one button.
private struct InFlightRowView: View {
    let model: AppModel
    let row: InFlightRow
    let dot: Palette.Token
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.palette(dot))
                    .frame(width: 8, height: 8)
                    .contrastOutline()
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: row.title)
                        .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(.palette(.text))
                        .lineLimit(1)
                    Text(verbatim: row.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.palette(.secondaryText))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: select)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(row.title), \(row.detail.replacing(" · ", with: ", "))")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, select)
            if let action = row.action {
                Button(action.title) { perform(action) }
                    .buttonStyle(PaletteButtonStyle(height: 26, fontSize: 12))
                    .accessibilityHint(row.title)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background(isSelected ? Color.palette(.selectedRow) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contextMenu { contextMenu }
    }

    @ViewBuilder private var contextMenu: some View {
        if case .attention(let item) = row.source {
            switch item.id {
            case .review(let id):
                Button("Mark reviewed") { Task { await model.markReviewed(id) } }
            case .check(let taskID):
                Button("Dismiss") { Task { await model.dismissCheck(taskID) } }
            case .report(let id):
                Button("Dismiss") { Task { await model.dismissReport(id) } }
            }
        }
    }

    private func perform(_ action: InFlightRow.Action) {
        switch action {
        case .switchTo:
            if let request = row.switchRequest { model.requestSwitch(request) }
        case .openAgent:
            if let linkID = row.linkID { Task { await model.openAgent(linkID, handling: row.attentionItemID) } }
        case .stopWaiting:
            if case .thread(.waiting(let taskID)) = row.id { Task { await model.stopWaiting(taskID) } }
        }
    }
}

/// The selected row: its title and state, the agent's output as plain text,
/// and the owner's choices.
private struct InFlightInspector: View {
    let model: AppModel
    let row: InFlightRow

    private var review: ReviewItem? {
        guard case .attention(.review(let id)) = row.id else { return nil }
        return model.reviewItems.first { $0.id == id }
    }

    private var report: (item: AttentionItem, report: AgentReport)? {
        guard case .attention(let item) = row.source, let report = item.report else { return nil }
        return (item, report)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: row.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.palette(.text))
                    .fixedSize(horizontal: false, vertical: true)
                statusLine
            }
            if let report {
                ScrollView {
                    ReportRow(model: model, item: report.item, report: report.report)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let review {
                output(review)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
            }
            if let notice = model.agentNotice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.palette(.amberText))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if report == nil { buttons }
        }
        .padding(EdgeInsets(top: 22, leading: 20, bottom: 22, trailing: 20))
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.palette(row.inspectorDot))
                .frame(width: 7, height: 7)
                .contrastOutline()
                .accessibilityHidden(true)
            Text(verbatim: row.statusLine)
                .font(.system(size: 12))
                .foregroundStyle(.palette(row.inspectorText))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.statusLine.replacing(" · ", with: ", "))
    }

    private func output(_ review: ReviewItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OUTPUT")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.88)
                .foregroundStyle(.palette(.secondaryText))
                .accessibilityAddTraits(.isHeader)
            ScrollView {
                // Verbatim: agent output is never interpreted as markup.
                Text(verbatim: review.output?.lines.joined(separator: "\n") ?? "The agent’s screen could not be read.")
                    .font(.system(size: 12, design: .monospaced))
                    .lineSpacing(4)
                    .foregroundStyle(.palette(.text))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
            }
            .frame(maxHeight: 300)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color.palette(.window), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.palette(.separator)))
        }
    }

    private var buttons: some View {
        VStack(spacing: 8) {
            if let linkID = row.linkID {
                Button("Open agent") { Task { await model.openAgent(linkID, handling: row.attentionItemID) } }
                    .buttonStyle(PaletteButtonStyle(height: 30, fontSize: 13, fillsWidth: true))
            }
            if let request = row.switchRequest {
                Button("Switch to this") { model.requestSwitch(request) }
                    .buttonStyle(PaletteButtonStyle(height: 30, fontSize: 13, fillsWidth: true, isProminent: true))
            }
        }
    }
}

/// The boards' small bordered button, and its filled accent form.
struct PaletteButtonStyle: ButtonStyle {
    let height: CGFloat
    let fontSize: CGFloat
    var fillsWidth = false
    var isProminent = false
    var horizontalPadding: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: isProminent ? .semibold : .regular))
            .foregroundStyle(isProminent ? Color.white : .palette(.text))
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(height: height)
            .background(Color.palette(isProminent ? .accent : .buttonBackground), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                if !isProminent { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.palette(.buttonBorder)) }
            }
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private extension InFlightRow.Action {
    var title: String {
        switch self {
        case .switchTo: "Switch"
        case .openAgent: "Open agent"
        case .stopWaiting: "Stop waiting"
        }
    }
}

private extension InFlightRow {
    var attentionItemID: AttentionItem.ID? {
        if case .attention(let id) = self.id { id } else { nil }
    }

    var inspectorDot: Palette.Token {
        switch status {
        case .resultsReady: .green
        case .approval, .check, .report: .amber
        case .working: .accent
        case .waiting: .idleDot
        }
    }

    var inspectorText: Palette.Token {
        switch status {
        case .resultsReady: .greenText
        case .approval, .check, .report: .amberText
        case .working, .waiting: .secondaryText
        }
    }
}
