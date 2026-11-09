import FocusPilotCore
import SwiftUI

/// Starts a session (design 11): duration, mode, the projects it covers
/// (all by default, #56) and the planned end, and the pre-flight Browsers
/// and Apps rows (#17). Nothing needs to be in Now.
struct StartFocusSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    private enum Duration: Hashable {
        case minutes(Int), custom
    }

    @State private var duration: Duration
    @State private var customMinutes = 30
    @State private var mode: SessionMode
    @State private var coversAll = true
    @State private var chosen: Set<Int64> = []
    @State private var isStarting = false

    init(model: AppModel) {
        self.model = model
        _duration = State(initialValue: .minutes(model.sessionPreferences.defaultMinutes))
        _mode = State(initialValue: model.sessionPreferences.strictByDefault ? .strict : .normal)
    }

    private var minutes: Int {
        if case .minutes(let value) = duration { value } else { customMinutes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Start focus")
                    .font(.title3.weight(.semibold))
                if let task = model.nowTask {
                    Text(task.title)
                        .font(.title2.weight(.semibold))
                    // The return cue comes first when there is one (#20).
                    if let wrapUp = task.wrapUp {
                        ReturnCueView(wrapUp: wrapUp)
                            .padding(.top, 6)
                    } else if let nextAction = task.nextAction {
                        Text(nextAction)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Nothing in Now")
                        .foregroundStyle(.secondary)
                }
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 16) {
                GridRow {
                    label("Duration")
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Duration", selection: $duration) {
                            Text("25 min").tag(Duration.minutes(25))
                            Text("50 min").tag(Duration.minutes(50))
                            Text("90 min").tag(Duration.minutes(90))
                            Text("Custom…").tag(Duration.custom)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        if duration == .custom {
                            Stepper("\(customMinutes) min", value: $customMinutes, in: 5...240, step: 5)
                                .fixedSize()
                        }
                    }
                }
                GridRow {
                    label("Mode")
                    Picker("Mode", selection: $mode) {
                        Text("Normal").tag(SessionMode.normal)
                        Text("Strict").tag(SessionMode.strict)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
                GridRow {
                    label("Projects")
                    projectsChoice
                }
                if model.snapshot.isObserveOnly {
                    GridRow {
                        label("Blocking")
                        ObservingLine(model: model, showsWeek: false)
                    }
                } else {
                    GridRow {
                        label("Browsers")
                        BrowserStatusLine(status: model.browserProtection)
                    }
                    GridRow {
                        label("Apps")
                        Text(AppProtectionText.preflight(rules: model.ruleSets, at: .now))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let error = model.sessionError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            Divider()
            HStack {
                Text(SessionText.endsAt(.now.addingTimeInterval(TimeInterval(minutes * 60)), from: .now, timeZone: .current))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                // Design 11: starting with partial protection is a deliberate choice.
                // Observing blocks nothing by choice, so there is nothing to start anyway.
                Button(model.browserProtection.level == .protected || model.snapshot.isObserveOnly
                       ? "Start focus" : "Start anyway", action: start)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isStarting || (!coversAll && chosen.isEmpty))
                    .accessibilityHint(model.nowTask.map { "Starts a session for \($0.title)" } ?? "")
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    /// Projects listed with their titles; "No project" has no id and is never chosen.
    private var choosable: [ProjectSummary] {
        model.projects.filter { $0.id != nil }
    }

    @ViewBuilder
    private var projectsChoice: some View {
        VStack(alignment: .leading, spacing: 6) {
            if choosable.isEmpty {
                Text("All projects")
            } else {
                Picker("Projects", selection: $coversAll) {
                    Text("All projects").tag(true)
                    Text("Chosen projects").tag(false)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                if !coversAll {
                    // Long lists scroll, so the sheet keeps its buttons on screen.
                    if choosable.count > 6 {
                        ScrollView { projectToggles }
                            .frame(height: 150)
                    } else {
                        projectToggles
                    }
                }
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

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.leading)
    }

    private func start() {
        isStarting = true
        Task {
            if await model.startSession(minutes: minutes, mode: mode, projects: coversAll ? [] : Array(chosen)) {
                dismiss()
            }
            isStarting = false
        }
    }
}
