import FocusPilotCore
import SwiftUI

/// The planning window sidebar (#70, redesign Main): Today, In flight,
/// Projects, Review queue and Settings with grey count pills that hide at
/// zero, and a one-line protection footer. Labs stays hidden until its ticket.
/// The up and down arrows move between pages, as in a list.
struct PlanningSidebar: View {
    let model: AppModel
    @Binding var page: PlanningView.Page?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                row(.today, "Today", "sun.max")
                row(.inFlight, "In flight", "arrow.turn.up.right", count: model.attention.count)
                row(.projects, "Projects", "folder")
                row(.review, "Review queue", "tray", count: model.inFlightBoard.results.count)
                row(.settings, "Settings", "gearshape")
            }
            .padding(.horizontal, 10)
            // Below the window's close, minimize and zoom buttons.
            .padding(.top, 48)
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(.upArrow) { move(-1) }
            .onKeyPress(.downArrow) { move(1) }
            Spacer(minLength: 0)
            SidebarFooterLine(footer: SidebarFooter(protection: model.browserProtection,
                                                    observing: model.snapshot.isObserveOnly))
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.palette(.sidebar))
    }

    private func move(_ offset: Int) -> KeyPress.Result {
        page = (page ?? .today).moved(by: offset)
        return .handled
    }

    private func row(_ target: PlanningView.Page, _ title: String, _ symbol: String, count: Int = 0) -> some View {
        let selected = page == target || (page == nil && target == .today)
        return Button {
            page = target
            isFocused = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text(title)
                    .fontWeight(selected ? .medium : .regular)
                Spacer(minLength: 4)
                if let badge = SidebarBadge.text(count) {
                    Text(badge)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.palette(.badgeText))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(Color.palette(.badge), in: Capsule())
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(.palette(.text))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(selected ? Color.palette(.sidebarSelection) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? "\(title), \(count)" : title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// "Chrome protected" with a green dot, or the real state with an amber or
/// hollow grey dot.
struct SidebarFooterLine: View {
    let footer: SidebarFooter

    var body: some View {
        HStack(spacing: 8) {
            Group {
                switch footer.tone {
                case .green: Circle().fill(Color.palette(.green))
                case .amber: Circle().fill(Color.palette(.amber))
                case .unknown: Circle().strokeBorder(Color.palette(.secondaryText), lineWidth: 1)
                }
            }
            .frame(width: 8, height: 8)
            .contrastOutline()
            .accessibilityHidden(true)
            Text(footer.text)
                .font(.system(size: 12))
                .foregroundStyle(.palette(.footerText))
                .lineLimit(1)
        }
        .help(footer.help)
        .accessibilityElement(children: .combine)
    }
}

/// The page title, the date on Today, and New Task (#70, redesign Main).
struct PlanningHeader: View {
    let title: String
    let date: String?
    let newTask: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.palette(.text))
                    .accessibilityAddTraits(.isHeader)
                if let date {
                    Text(date)
                        .font(.system(size: 12))
                        .foregroundStyle(.palette(.secondaryText))
                }
            }
            Spacer()
            Button(action: newTask) {
                Label("New Task", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 13))
                    .foregroundStyle(.palette(.text))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color.palette(.buttonBackground), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.palette(.buttonBorder)))
            }
            .buttonStyle(.plain)
            .help("New Task (⌘N)")
        }
        .padding(EdgeInsets(top: 14, leading: 24, bottom: 10, trailing: 24))
        .overlay(alignment: .bottom) { Rectangle().fill(Color.palette(.separator)).frame(height: 1) }
    }
}
