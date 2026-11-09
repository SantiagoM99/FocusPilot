import FocusPilotCore
import SwiftUI

/// The "New task" sheet. The owner types the task and its deadline in one
/// field ("Write NLP report by Friday 11pm"); the sheet previews the split
/// title and the deadline's reading, both correctable, before saving
/// (redesign Sheets, #71).
struct QuickCaptureSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    /// Split and parsed once per text change; Save stores exactly this.
    @State private var draft = CaptureDraft()
    @State private var isEditingDeadline = false
    /// What the open picker shows before the owner picks: the deadline, or
    /// today. Only a change in the picker, or Done on today's proposal,
    /// commits it.
    @State private var proposal: Deadline?
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New task")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.palette(.text))

            VStack(alignment: .leading, spacing: 6) {
                Text("Task")
                    .font(.system(size: 12))
                    .foregroundStyle(.palette(.secondaryText))
                TextField("Task", text: $text, prompt: Text("Write NLP report by Friday 5pm"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14))
                if let hint = draft.unrecognizedDateHint {
                    Label(hint, systemImage: "questionmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.palette(.secondaryText))
                }
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    fieldLabel("Title")
                    TextField("Title", text: $draft.title, prompt: Text(""))
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .fontWeight(.medium)
                }
                GridRow {
                    fieldLabel("Deadline")
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        DeadlinePreview(deadlineText: draft.deadlineText, deadline: draft.deadline)
                        Button("Change") {
                            proposal = draft.proposedDeadline(now: .now, timeZone: .current)
                            isEditingDeadline.toggle()
                        }
                        .buttonStyle(PaletteButtonStyle(height: 22, cornerRadius: 5, fontSize: 12, horizontalPadding: 8))
                        .accessibilityHint("Opens a date picker")
                        .popover(isPresented: $isEditingDeadline, arrowEdge: .bottom) { deadlineEditor }
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
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                }
            }
            .font(.system(size: 13))
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.palette(.nowTint), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.palette(.nowBorder)))

            if let taskError = model.taskError {
                Label(taskError, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.palette(.amber))
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.palette)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(PaletteButtonStyle(kind: .primary, horizontalPadding: 16))
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.newTask == nil || isSaving)
            }
        }
        .padding(EdgeInsets(top: 22, leading: 22, bottom: 18, trailing: 22))
        .frame(width: 460)
        .background { Color.palette(.window) }
        .onChange(of: text) {
            draft.setText(text, now: .now, timeZone: .current, isKnownWord: SpellingDictionary.isKnown)
            isEditingDeadline = false
        }
    }

    /// Changes commit as the picker moves; Done also commits today's
    /// proposal, which the owner may accept untouched.
    @ViewBuilder private var deadlineEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let shown = draft.deadline ?? proposal {
                DeadlineEditor(deadline: Binding(get: { shown }, set: { draft.correctDeadline($0) }))
                HStack {
                    if draft.deadline != nil || draft.deadlineText != nil {
                        Button("Remove Deadline") {
                            draft.removeDeadline()
                            isEditingDeadline = false
                        }
                        .buttonStyle(.link)
                    }
                    Spacer()
                    Button("Done") {
                        draft.confirmPicker(shown)
                        isEditingDeadline = false
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.palette(.secondaryText))
            .frame(width: 84, alignment: .leading)
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
