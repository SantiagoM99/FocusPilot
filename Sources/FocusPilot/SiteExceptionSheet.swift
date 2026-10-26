import FocusPilotCore
import SwiftUI

/// A timed exception for a blocked site or one of its pages, asked from the
/// app (#14); the blocked page in Chrome asks the same coordinator (design
/// 05B, ExceptionRequestForm). A strict session needs a reason, a
/// confirmation and the wait, as everywhere else.
struct SiteExceptionSheet: View {
    struct Draft: Identifiable {
        let id = UUID()
        /// The rule's site, or a page on it, to start from.
        var site: String
    }

    let model: AppModel
    @State private var typed: String
    @State private var wholeSite = true
    @State private var duration = TimedException.durations[1]
    @State private var reason = ""
    @State private var isConfirming = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, draft: Draft) {
        self.model = model
        _typed = State(initialValue: draft.site)
    }

    private var isStrict: Bool { model.snapshot.activeSession?.mode == .strict }
    private var domain: String { SiteDomain.normalized(typed) ?? typed.trimmingCharacters(in: .whitespaces) }
    private var namesAPage: Bool { SiteDomain.namesAPage(typed) }
    private var scope: ExceptionScope? { ExceptionScope.requested(typed, wholeSite: wholeSite || !namesAPage) }

    /// When a confirmed strict request for this scope may be granted.
    private var availableAt: Date? {
        guard let pending = model.snapshot.pendingException, let scope, (try? scope.normalized()) == pending.scope,
              pending.duration == duration else { return nil }
        return pending.availableAt
    }

    var body: some View {
        let availableAt = availableAt
        let waiting = availableAt.map { model.now < $0 } ?? false
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Timed exception").font(.headline)
                Spacer()
                if isStrict {
                    Label("Strict", systemImage: "lock.fill").font(.callout).foregroundStyle(.secondary)
                }
            }
            Text("Applies in every Chrome profile. Ends at the time chosen, not at the session end.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Form {
                TextField("Site or page", text: $typed, prompt: Text("youtube.com/watch?v=…"))
                    .disabled(availableAt != nil)
                Picker("Scope", selection: $wholeSite) {
                    Label("All of \(domain)", systemImage: "globe").tag(true)
                    Label("Only this page", systemImage: "doc").tag(false)
                        .selectionDisabled(!namesAPage)
                }
                .pickerStyle(.radioGroup)
                .disabled(availableAt != nil)
                Picker("Duration", selection: $duration) {
                    ForEach(TimedException.durations, id: \.self) { duration in
                        Text("\(Int(duration / 60)) min").tag(duration)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .disabled(availableAt != nil)
                if isStrict {
                    TextField("Reason", text: $reason, prompt: Text(wholeSite || !namesAPage ? "Why this site is needed for the task" : "Why this page is needed for the task"))
                        .disabled(availableAt != nil)
                }
            }
            .formStyle(.columns)
            if !namesAPage, !wholeSite {
                Text("Type a page address to allow only that page.").font(.callout).foregroundStyle(.secondary)
            }
            if isConfirming {
                Text("A strict session waits \(StrictEarlyEnd.waitText) before allowing it.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error {
                Text(error).font(.callout).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    if availableAt != nil { Task { await model.cancelException() } }
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(allowLabel(availableAt: availableAt)) { request() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(scope == nil || waiting || (isStrict && reason.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { wholeSite = !namesAPage }
    }

    private func allowLabel(availableAt: Date?) -> String {
        if isConfirming { return "Start the wait" }
        if availableAt == nil { return "Allow for \(Int(duration / 60)) min" }
        return BlockedAppText.allowButton(availableAt: availableAt, now: model.now)
    }

    private func request() {
        guard let scope else { return }
        Task {
            let outcome = await model.requestException(scope, duration: duration, reason: reason, confirmed: isConfirming)
            error = model.exceptionError
            switch outcome {
            case .granted?: dismiss()
            case .needsConfirmation?: isConfirming = true
            case .waitUntil?: isConfirming = false
            case nil: break
            }
        }
    }
}
