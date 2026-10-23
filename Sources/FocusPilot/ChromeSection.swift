import AppKit
import FocusPilotCore
import SwiftUI

/// Settings › Blocking › Chrome: each profile's acknowledgement and
/// incognito access (#16), and where to load the extension once. The full
/// protection status arrives with #17.
struct ChromeSection: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Chrome", note: "Each profile acknowledges the policy separately")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.chromeProfiles.enumerated()), id: \.element.id) { index, profile in
                    if index > 0 { Divider() }
                    ChromeProfileRow(profile: profile) { model.forgetChromeProfile(profile.profileID) }
                }
                if model.chromeProfiles.isEmpty {
                    LoadExtensionSteps(setup: model.chromeSetup)
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            if !model.chromeProfiles.isEmpty, let setup = model.chromeSetup {
                Button("Show Extension Folder") { NSWorkspace.shared.activateFileViewerSelecting([setup.extensionFolder]) }
                    .controlSize(.small)
                Text("To add another Chrome profile, load this folder there too.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ChromeProfileRow: View {
    let profile: ChromeProfileStatus
    let forget: () -> Void

    private var isDisconnected: Bool {
        if case .disconnected = profile.state { true } else { false }
    }

    private var color: Color {
        switch profile.state {
        case .acknowledged: .green
        case .syncing, .waiting: .orange
        case .disconnected: .secondary
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                // Chrome gives extensions no profile name; the ID's start tells them apart.
                Text("Profile \(profile.profileID.prefix(4))")
                Text(details).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            // A connected profile's host would write the record right back.
            if isDisconnected {
                Button("Forget", action: forget)
                    .controlSize(.small)
                    .help("Remove this profile from the list. It comes back if it connects again.")
            }
        }
        .padding(10)
    }

    private var details: String {
        var parts = [ChromeProfileStatus.text(profile.state)]
        parts.append(profile.incognitoAllowed ? "Incognito allowed" : "Incognito not allowed")
        if !profile.allSitesAccess { parts.append("Site access limited") }
        if profile.missingObservations > 0 { parts.append("\(profile.missingObservations) reports lost") }
        return parts.joined(separator: " · ")
    }
}

/// First-time setup: Chrome loads the unpacked extension from a folder.
private struct LoadExtensionSteps: View {
    let setup: ChromeSetup?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Not connected yet").font(.headline)
            if let problem = setup?.problem {
                Text(problem).foregroundStyle(.orange)
            }
            Text("In Chrome, open chrome://extensions, turn on Developer mode, click Load unpacked and choose the FocusPilot extension folder. You only do this once per Chrome profile.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let setup {
                HStack {
                    Button("Show Extension Folder") { NSWorkspace.shared.activateFileViewerSelecting([setup.extensionFolder]) }
                    Button("Copy Folder Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(setup.extensionFolder.path, forType: .string)
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
