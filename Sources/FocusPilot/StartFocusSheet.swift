import FocusPilotCore
import SwiftUI

/// Starts a session on the Now task (design 11): duration, mode, and the
/// planned end. Rules and the pre-flight check arrive with #12, #13 and #17.
struct StartFocusSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    private enum Duration: Hashable {
        case minutes(Int), custom
    }

    @State private var duration = Duration.minutes(50)
    @State private var customMinutes = 30
    @State private var mode = SessionMode.normal
    @State private var isStarting = false

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
                        modeOption("Normal", "Ends at the planned end. If FocusPilot quits, rules still lift at the planned end.")
                            .tag(SessionMode.normal)
                        modeOption("Strict", "Ending early needs confirmation and a wait. If FocusPilot quits, rules stay until it runs again.")
                            .tag(SessionMode.strict)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
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
                Button("Start focus", action: start)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.nowTask == nil || isStarting)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.leading)
    }

    private func modeOption(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 6)
    }

    private func start() {
        isStarting = true
        Task {
            if await model.startSession(minutes: minutes, mode: mode) {
                dismiss()
            }
            isStarting = false
        }
    }
}
