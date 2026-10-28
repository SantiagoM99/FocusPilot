import FocusPilotCore
import SwiftUI

/// Settings › Allowed: apps, sites and tools that never trigger a check-in.
/// Seeded tools are listed like the owner's own and can be removed.
struct AllowedSettings: View {
    let model: AppModel
    @State private var selection: Int64?
    @State private var isAddingSite = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Allowed apps and sites", note: "Never trigger a check-in")
                VStack(spacing: 0) {
                    List(selection: $selection) {
                        ForEach(model.allowed, id: \.id) { entry in
                            HStack {
                                Text(title(entry))
                                Spacer()
                                Text(entry.source == .seeded ? "Seeded" : "Added")
                                    .font(.callout)
                                    .foregroundStyle(.tertiary)
                            }
                            .tag(entry.id)
                        }
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 240)
                    Divider()
                    HStack(spacing: 4) {
                        Menu {
                            Button("Add Site…") { isAddingSite = true }
                            Button("Add App…") {
                                if let app = AppPicker.choose() {
                                    Task { await model.allow(AllowedActivity(name: app.displayName, target: app)) }
                                }
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add app or site")
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Add an app or site")
                        Button("Remove", systemImage: "minus") {
                            if let selection { Task { await model.removeAllowed(selection) } }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .disabled(selection == nil)
                        Spacer()
                    }
                    .padding(6)
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                SettingsError(message: model.rulesError)
                Text("Check-ins for unknown apps and sites arrive later (#21); this list is what they will skip.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .sheet(isPresented: $isAddingSite) {
            AllowSiteSheet(model: model)
        }
    }

    /// "Overleaf · overleaf.com", "Finder", "Herdr · command-line tool".
    private func title(_ entry: AllowedActivity) -> String {
        switch entry.target {
        case .site(let domain): entry.name == domain ? domain : "\(entry.name) · \(domain)"
        case .app: entry.name
        case .tool: "\(entry.name) · command-line tool"
        }
    }
}

private struct AllowSiteSheet: View {
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
