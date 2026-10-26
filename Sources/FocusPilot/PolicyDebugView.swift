import FocusPilotCore
import SwiftUI

/// Settings › Blocking: one collapsed "Show technical details" with the
/// policy revision, checksum, what each Chrome profile applied and the exact
/// JSON the extensions receive. These are diagnostics; the rest of the UI
/// speaks plainly (decision 0003, 2026-10-26).
struct PolicyDebugView: View {
    let policy: CompiledPolicy?
    var profiles: [ChromeProfileStatus] = []
    @State private var isExpanded: Bool

    init(policy: CompiledPolicy?, profiles: [ChromeProfileStatus] = [], isExpanded: Bool = false) {
        self.policy = policy
        self.profiles = profiles
        _isExpanded = State(initialValue: isExpanded)
    }

    var body: some View {
        if let policy {
            DisclosureGroup("Show technical details", isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Policy rev. \(policy.revision) · compiled \(policy.effectiveAt.formatted(date: .omitted, time: .shortened)) · checksum \(policy.checksum.prefix(8))")
                    ForEach(profiles) { profile in
                        Text("Profile \(profile.profileID.prefix(4)) · \(applied(profile.state))")
                    }
                    Text("Compiled policy")
                    ScrollView(.horizontal) {
                        Text(json(policy))
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .background(.background, in: RoundedRectangle(cornerRadius: 6))
                }
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .font(.callout)
        }
    }

    private func applied(_ state: ChromeProfileStatus.State) -> String {
        switch state {
        case .acknowledged(let revision): "applied rev. \(revision)"
        case .syncing(let acknowledged): "applied rev. \(acknowledged), updating"
        case .waiting: "nothing applied yet"
        case .disconnected: "disconnected"
        }
    }

    private func json(_ policy: CompiledPolicy) -> String {
        (try? policy.json(pretty: true)).map { String(decoding: $0, as: UTF8.self) } ?? "Could not encode the policy."
    }
}
