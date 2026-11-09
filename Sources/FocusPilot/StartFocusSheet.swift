import FocusPilotCore
import SwiftUI

/// Starts a session (redesign Sheets, #71): the Now summary, the length,
/// strict or not and the projects it covers (all by default, #56). Nothing
/// needs to be in Now. The browser line shows only when protection is less
/// than full, the case Start anyway is for (design 11).
struct StartFocusSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    private enum Length: Hashable {
        case minutes(Int), custom
    }

    @State private var length = Length.minutes(50)
    @State private var customMinutes = 30
    @State private var isStrict = false
    @State private var coversAll = true
    @State private var chosen: Set<Int64> = []
    @State private var isStarting = false

    private var minutes: Int {
        if case .minutes(let value) = length { value } else { customMinutes }
    }

    private var isFullyProtected: Bool {
        model.browserProtection.level == .protected || model.snapshot.isObserveOnly
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Start focus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.palette(.text))
            nowSummary
            lengthChoice
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Strict session")
                    Spacer()
                    Toggle("Strict session", isOn: $isStrict)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                projectsChoice
            }
            .font(.system(size: 13))
            .foregroundStyle(.palette(.text))

            if !isFullyProtected {
                BrowserStatusLine(status: model.browserProtection, showsDetail: false)
            }
            if let error = model.sessionError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.palette(.amber))
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.palette)
                    .keyboardShortcut(.cancelAction)
                Button(action: start) {
                    Label(isFullyProtected ? "Start" : "Start anyway", systemImage: "play.fill")
                }
                .buttonStyle(PaletteButtonStyle(kind: .primary, horizontalPadding: 16))
                .keyboardShortcut(.defaultAction)
                .disabled(isStarting || (!coversAll && chosen.isEmpty))
                .accessibilityHint(model.nowTask.map { "Starts a session for \($0.title)" } ?? "")
            }
        }
        .padding(EdgeInsets(top: 22, leading: 22, bottom: 18, trailing: 22))
        .frame(width: 460)
        .background { Color.palette(.window) }
    }

    private var nowSummary: some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionTitle("Now", color: .palette(.nowLabel))
            // A space keeps the title's height when Now is empty.
            Text(model.nowTask?.title ?? " ")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.palette(.text))
            if let summary = model.nowTask?.focusSummary(at: .now) {
                Text(verbatim: summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.palette(.secondaryText))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.palette(.nowTint), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.palette(.nowBorder)))
    }

    private var lengthChoice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Length")
                .font(.system(size: 12))
                .foregroundStyle(.palette(.secondaryText))
            HStack(spacing: 0) {
                lengthSegment("25 min", .minutes(25))
                lengthSegment("50 min", .minutes(50))
                lengthSegment("90 min", .minutes(90))
                lengthSegment("Custom…", .custom)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.palette(.buttonBorder)))
            if length == .custom {
                Stepper("\(customMinutes) min", value: $customMinutes, in: 5...240, step: 5)
                    .font(.system(size: 13))
                    .fixedSize()
            }
        }
    }

    private func lengthSegment(_ title: String, _ value: Length) -> some View {
        let selected = length == value
        return Button { length = value } label: {
            Text(title)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.white : Color.palette(.text))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(selected ? Color.palette(.accent) : Color.palette(.buttonBackground))
                .contentShape(Rectangle())
                .overlay(alignment: .leading) {
                    if value != .minutes(25) {
                        Rectangle().fill(Color.palette(.buttonBorder)).frame(width: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Projects listed with their titles; "No project" has no id and is never chosen.
    private var choosable: [ProjectSummary] {
        model.projects.filter { $0.id != nil }
    }

    @ViewBuilder
    private var projectsChoice: some View {
        HStack {
            Text("Projects allowed")
            Spacer()
            if choosable.isEmpty {
                Text("All projects")
                    .foregroundStyle(.palette(.secondaryText))
            } else {
                Picker("Projects allowed", selection: $coversAll) {
                    Text("All projects").tag(true)
                    Text("Chosen projects").tag(false)
                }
                .labelsHidden()
                .fixedSize()
            }
        }
        if !coversAll, !choosable.isEmpty {
            // Long lists scroll, so the sheet keeps its buttons on screen.
            if choosable.count > 6 {
                ScrollView { projectToggles }
                    .frame(height: 150)
            } else {
                projectToggles
            }
        }
    }

    private var projectToggles: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(choosable, id: \.id) { project in
                Toggle(project.title, isOn: Binding(
                    get: { project.id.map(chosen.contains) ?? false },
                    set: { isOn in
                        guard let id = project.id else { return }
                        if isOn { chosen.insert(id) } else { chosen.remove(id) }
                    }))
            }
        }
        .padding(.leading, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func start() {
        isStarting = true
        Task {
            if await model.startSession(minutes: minutes, mode: isStrict ? .strict : .normal, projects: coversAll ? [] : Array(chosen)) {
                dismiss()
            }
            isStarting = false
        }
    }
}
