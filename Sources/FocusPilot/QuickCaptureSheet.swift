import FocusPilotCore
import SwiftUI

/// The "New task" sheet. The owner types the task and its deadline in one
/// field ("Write NLP report by Friday 11pm"); the sheet previews the split
/// title and the deadline's reading, both correctable, before saving.
struct QuickCaptureSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    /// Split and parsed once per text change; Save stores exactly this.
    @State private var draft = CaptureDraft()
    @State private var isEditingDeadline = false
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New task")
                .font(.title3.weight(.semibold))
            Text("Type the task and when it's due. Nothing is saved until you confirm the interpretation below.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("Task", text: $text)
                .font(.title3)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    fieldLabel("Title")
                    TextField("Title", text: $draft.title, prompt: Text(""))
                }
                GridRow {
                    fieldLabel("Deadline")
                    VStack(alignment: .leading, spacing: 8) {
                        DeadlinePreview(deadlineText: draft.deadlineText, deadline: draft.deadline)
                        if draft.deadlineText != nil {
                            Button("Remove deadline") {
                                draft.removeDeadline()
                                isEditingDeadline = false
                            }
                            .buttonStyle(.link)
                        }
                        if isEditingDeadline, let deadline = draft.deadline {
                            DeadlineEditor(deadline: Binding(get: { deadline }, set: { draft.correctDeadline($0) }))
                        }
                    }
                }
                GridRow {
                    fieldLabel("Project")
                    ProjectPicker(projectTitles: model.projectTitles, projectName: $draft.projectName)
                }
                GridRow {
                    fieldLabel("Next action")
                    TextField("Next action", text: Binding(get: { draft.nextAction ?? "" }, set: { draft.nextAction = $0 }),
                              prompt: Text("Optional"))
                }
            }

            if let taskError = model.taskError {
                Label(taskError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                if let deadline = draft.deadline {
                    Button(deadline.wallClockTime == nil ? "Add a time…" : "Change date or time zone…") {
                        isEditingDeadline.toggle()
                    }
                }
                Spacer()
                Button(role: .cancel) { dismiss() } label: {
                    HStack(spacing: 6) {
                        Text("Cancel")
                        KeyHint("esc")
                    }
                }
                .keyboardShortcut(.cancelAction)
                Button(action: save) {
                    HStack(spacing: 6) {
                        Text("Save")
                        KeyHint("⏎")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.newTask == nil || isSaving)
            }
        }
        .padding(16)
        .frame(width: 520)
        .onChange(of: text) {
            draft.setText(text, now: .now, timeZone: .current)
            isEditingDeadline = false
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    private func save() {
        guard let newTask = draft.newTask, !isSaving else { return }
        isSaving = true
        Task {
            if await model.capture(newTask) {
                dismiss()
            }
            isSaving = false
        }
    }
}

/// A keyboard shortcut chip shown inside a button, e.g. "esc" or "⏎".
private struct KeyHint: View {
    let key: String

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(key)
            .font(.subheadline)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
            .accessibilityHidden(true)
    }
}
