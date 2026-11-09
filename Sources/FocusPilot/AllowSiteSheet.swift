import FocusPilotCore
import SwiftUI

/// Adds a site to Settings › Blocking › Always allowed.
struct AllowSiteSheet: View {
    let model: AppModel
    @State private var typed = ""
    @State private var name = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Allow a Site").font(.title3).padding([.horizontal, .top], 20)
            Form {
                TextField("Site", text: $typed, prompt: Text("scholar.google.com"))
                TextField("Name", text: $name, prompt: Text("Optional"))
                SettingsError(message: error ?? model.rulesError)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Allow") { allow() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(20)
        }
        .frame(width: 420)
        .onAppear { model.rulesError = nil }
    }

    private func allow() {
        guard let domain = SiteDomain.normalized(typed) else {
            error = "“\(typed)” isn't a site address."
            return
        }
        error = nil
        let title = name.trimmingCharacters(in: .whitespaces)
        Task {
            if await model.allow(AllowedActivity(name: title.isEmpty ? domain : title, target: .site(domain: domain))) { dismiss() }
        }
    }
}
