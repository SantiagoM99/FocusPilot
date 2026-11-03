import FocusPilotCore
import SwiftUI

/// Switch (decision 0004): one optional line about where the owner left
/// off, saved as the current task's return cue; then the target becomes Now
/// and its agent opens. Return confirms, Esc cancels and changes nothing.
struct SwitchSheet: View {
    let model: AppModel
    let request: SwitchRequest
    @State private var note = ""
    @State private var isSwitching = false
    @FocusState private var isNoteFocused: Bool

    private var current: TodayItem? {
        model.nowTask.flatMap { $0.id == request.taskID ? nil : $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Switch to “\(request.taskTitle)”")
                    .font(.headline)
                Text(request.opens)
                    .foregroundStyle(.secondary)
            }
            if let current {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Where did you leave off?")
                    TextField("Optional", text: $note, axis: .vertical)
                        .labelsHidden()
                        .accessibilityLabel("Where did you leave off?")
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)
                        .focused($isNoteFocused)
                        .onSubmit(confirm)
                    Text("Saved on “\(current.title)” and shown first when you come back to it.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { model.switchRequest = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Switch", action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(isSwitching)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { isNoteFocused = true }
    }

    private func confirm() {
        guard !isSwitching else { return }
        isSwitching = true
        Task { await model.confirmSwitch(note: note) }
    }
}

/// Mark as waiting (decision 0004): what the task waits on, and when to
/// check on it again; a due check appears under Needs you.
struct MarkWaitingSheet: View {
    let model: AppModel
    let taskID: Int64
    @State private var waitingOn = ""
    @State private var check = WaitingCheck.none

    private var task: TodayItem? { model.today.first { $0.id == taskID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mark as waiting")
                    .font(.headline)
                Text(task?.title ?? "")
                    .foregroundStyle(.secondary)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("Waiting on")
                        .foregroundStyle(.secondary)
                    TextField("Optional, for example Ana’s review", text: $waitingOn)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Waiting on")
                }
                GridRow {
                    Text("Check again")
                        .foregroundStyle(.secondary)
                    Picker("Check again", selection: $check) {
                        ForEach(WaitingCheck.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            Text("At that time the task appears under Needs you in In flight. Nothing opens on its own.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { model.markingWaiting = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Mark as waiting") {
                    model.markingWaiting = nil
                    Task { await model.markWaiting(taskID, on: waitingOn, checkAt: check.date(after: .now)) }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            if let current = model.waiting(for: taskID) { waitingOn = current.on ?? "" }
        }
    }
}
