import FocusPilotCore
import SwiftUI

/// Settings › Observe (design 12): observe-only for the baseline week, how
/// far it has got, this week's pilot measures and what is recorded.
struct ObserveSettings: View {
    let model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { model.snapshot.isObserveOnly },
                                     set: { on in Task { await model.setObserveOnly(on) } })) {
                    Text("Observe only — record activity, no blocking or nudges")
                    Text("Sessions still run and are timed; rules are not enforced.")
                }
                if let since = model.snapshot.observeSince {
                    LabeledContent("Observed so far", value: BaselineWeek(since: since, now: model.now).observedLine)
                }
                if let error = model.observeError {
                    SettingsError(message: error)
                }
            } footer: {
                Text(model.snapshot.isObserveOnly
                     ? "Turning this off applies your rules again right away."
                     : "Use it for a baseline week before blocking: the same measures, with nothing blocked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Last 7 days") {
                ForEach(model.weeklySummary?.lines ?? [], id: \.label) { line in
                    LabeledContent(line.label, value: line.value)
                }
            }
            Section("What is recorded") {
                Group {
                    Text("Only while observing, kept for 24 hours: which app is in front and the domain of Chrome's front tab.")
                    Text("Kept for the pilot: session starts and ends, exceptions, and blocked apps you opened; while observing, also resume times and visits to sites and apps your rules name. Times and durations, with their session and task.")
                    Text("Never stored: URLs, page titles or content, keystrokes or screenshots.")
                }
                .font(.callout)
            }
        }
        .formStyle(.grouped)
        .task { await model.loadWeeklySummary() }
    }
}
