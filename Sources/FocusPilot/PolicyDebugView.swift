import FocusPilotCore
import SwiftUI

/// "Policy rev. 41 · compiled 14:31" and, on request, the exact JSON the
/// extensions receive, for checking what a rule edit produced.
struct PolicyDebugView: View {
    let policy: CompiledPolicy?
    @State private var isShowingJSON: Bool

    init(policy: CompiledPolicy?, isShowingJSON: Bool = false) {
        self.policy = policy
        _isShowingJSON = State(initialValue: isShowingJSON)
    }

    var body: some View {
        if let policy {
            VStack(alignment: .leading, spacing: 8) {
                Text("Policy rev. \(policy.revision) · compiled \(policy.effectiveAt.formatted(date: .omitted, time: .shortened)) · checksum \(policy.checksum.prefix(8))")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                DisclosureGroup("Compiled policy", isExpanded: $isShowingJSON) {
                    ScrollView(.horizontal) {
                        Text(json(policy))
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .background(.background, in: RoundedRectangle(cornerRadius: 6))
                }
                .font(.callout)
                Text("Extensions receive this policy once Safari and Chrome support arrives (#13, #16).")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func json(_ policy: CompiledPolicy) -> String {
        (try? policy.json(pretty: true)).map { String(decoding: $0, as: UTF8.self) } ?? "Could not encode the policy."
    }
}
