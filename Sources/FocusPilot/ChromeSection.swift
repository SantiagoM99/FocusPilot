import AppKit
import FocusPilotCore
import SwiftUI

/// Settings › Chrome: the extension in each Chrome profile, other browsers
/// and the policy diagnostics.
struct ChromeSettings: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ChromeSection(model: model)
                OtherBrowsersSection()
                PolicyDebugView(policy: model.snapshot.policy, profiles: model.chromeProfiles)
            }
            .padding(24)
        }
    }
}

/// Each profile's acknowledgement and incognito access, and the buttons for
/// setting the extension up. The steps are in BUILDING.md.
private struct ChromeSection: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("PROFILES")
            SettingsCard {
                ForEach(Array(model.chromeProfiles.enumerated()), id: \.element.id) { index, profile in
                    if index > 0 { SettingsDivider() }
                    ChromeProfileRow(profile: profile) { model.forgetChromeProfile(profile.profileID) }
                }
                if model.chromeProfiles.isEmpty {
                    NotConnectedRow(problem: model.chromeSetup?.problem)
                }
            }
            if let setup = model.chromeSetup {
                ChromeSetupButtons(setup: setup)
                    .padding(.top, 4)
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
            Circle().fill(color).frame(width: 7, height: 7).contrastOutline().accessibilityHidden(true)
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

private struct NotConnectedRow: View {
    let problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Not connected yet").font(.system(size: 13)).foregroundStyle(.palette(.text))
            if let problem {
                Text(problem).font(.system(size: 12)).foregroundStyle(.palette(.amber))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Chrome loads the unpacked extension from a folder, once per profile.
private struct ChromeSetupButtons: View {
    let setup: ChromeSetup

    var body: some View {
        HStack {
            Button("Show Extension Folder") { NSWorkspace.shared.activateFileViewerSelecting([setup.extensionFolder]) }
            Button("Copy Folder Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(setup.extensionFolder.path, forType: .string)
            }
            if let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome"),
               let extensions = URL(string: "chrome://extensions") {
                Button("Open Chrome Extensions") {
                    NSWorkspace.shared.open([extensions], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration())
                }
            }
        }
        .controlSize(.small)
    }
}

/// Settings › Chrome › Other browsers (#17): Safari relies on
/// the owner's own blocker (decision 0003, 2026-10-20); the rest have no
/// FocusPilot extension.
struct OtherBrowsersSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("OTHER BROWSERS")
            SettingsCard {
                row("Safari", "Not verified")
                SettingsDivider()
                row("Firefox, Arc and others", "Not supported")
            }
        }
    }

    private func row(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().strokeBorder(.secondary, lineWidth: 1).frame(width: 7, height: 7).contrastOutline().accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
    }
}
