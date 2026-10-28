import FocusPilotCore
import SwiftUI

/// "Observing · nothing is blocked" over "Baseline week · day 4 of 7"
/// (design 12). A hollow gray dot, never green: observing is not protection.
struct ObservingLine: View {
    let model: AppModel
    var showsWeek = true

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label {
                Text("Observing · nothing is blocked")
            } icon: {
                Circle().strokeBorder(.secondary, lineWidth: 1).frame(width: 8, height: 8)
            }
            .font(.callout)
            if showsWeek, let since = model.snapshot.observeSince {
                Text(BaselineWeek(since: since, now: model.now).menuLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 22)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
