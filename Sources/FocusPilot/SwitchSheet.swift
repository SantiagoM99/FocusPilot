import FocusPilotCore
import SwiftUI

/// Switch (decision 0004; redesign, Parallel board at 14:13): one optional
/// line about where the owner left off, saved as the current task's return cue; then the target becomes Now
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
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "Switch to \(request.taskTitle)")
                    .font(.system(size: 14, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let current {
                    Text(verbatim: "Leaving \(current.title)")
                        .font(.system(size: 12))
                        .foregroundStyle(.palette(.secondaryText))
                }
            }
            if current != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Where did you leave off?")
                        .font(.system(size: 12))
                        .foregroundStyle(.palette(.secondaryText))
                    TextField("Where did you leave off?", text: $note, prompt: Text(verbatim: ""))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .focused($isNoteFocused)
                        .onSubmit(confirm)
                }
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { model.switchRequest = nil }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(PaletteButtonStyle(height: 28, fontSize: 13, horizontalPadding: 14))
                Button("Switch", action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(PaletteButtonStyle(height: 28, fontSize: 13, isProminent: true, horizontalPadding: 16))
                    .disabled(isSwitching)
            }
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
        .frame(width: 340)
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
                    TextField("Optional", text: $waitingOn)
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
