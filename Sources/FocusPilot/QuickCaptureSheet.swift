import FocusPilotCore
import SwiftUI

/// The "New task" sheet: title, deadline with a live preview of how it was
/// read, optional project and next action. Only the title is required.
struct QuickCaptureSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var deadlineText = ""
    /// The owner's correction of the parsed deadline; cleared when the
    /// deadline text changes, so the preview always follows the text.
    @State private var correctedDeadline: Deadline?
    @State private var isEditingDeadline = false
    @State private var projectName = ""
    @State private var nextAction = ""
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New task")
                .font(.title3.weight(.semibold))
            Text("Type the task and when it's due. Nothing is saved until you confirm the interpretation below.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    fieldLabel("Title")
                    TextField("Title", text: $title, prompt: Text("Write NLP report"))
                        .font(.title3)
                }
                GridRow {
                    fieldLabel("Deadline")
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Deadline", text: $deadlineText, prompt: Text("by Friday 11pm"))
                        DeadlinePreview(typedText: deadlineText, deadline: deadline)
                        if isEditingDeadline, let deadline {
                            DeadlineEditor(deadline: Binding(get: { deadline }, set: { correctedDeadline = $0 }))
                        }
                    }
                }
                GridRow {
                    fieldLabel("Project")
                    TextField("Project", text: $projectName, prompt: Text("Optional"))
                }
                GridRow {
                    fieldLabel("Next action")
                    TextField("Next action", text: $nextAction, prompt: Text("Optional"))
                }
            }

            if let taskError = model.taskError {
                Label(taskError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                if let deadline {
                    Button(deadline.wallClockTime == nil ? "Add a time…" : "Change date or time zone…") {
                        isEditingDeadline.toggle()
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(16)
        .frame(width: 520)
        .onChange(of: deadlineText) {
            correctedDeadline = nil
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    // MARK: State

    private var deadline: Deadline? {
        correctedDeadline ?? DeadlineParser(now: .now, timeZone: .current).parse(deadlineText)
    }

    private var newTask: NewTask {
        NewTask(title: title, projectName: projectName, deadline: deadline, nextAction: nextAction)
    }

    /// Typed deadline text that could not be read blocks saving: saving
    /// without it would silently drop what the owner typed.
    private var canSave: Bool {
        let deadlineUnreadable = !deadlineText.trimmingCharacters(in: .whitespaces).isEmpty && deadline == nil
        return newTask.isValid && !deadlineUnreadable && !isSaving
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        Task {
            if await model.capture(newTask) {
                dismiss()
            }
            isSaving = false
        }
    }
}
