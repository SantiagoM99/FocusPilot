import FocusPilotCore
import SwiftUI

/// Settings › Observe (design 12): observe-only for the baseline week, how
/// far it has got and this week's pilot measures. What is recorded is in
/// docs/DATA_AND_MEMORY.md, not on screen (decision 0003, 2026-11-03).
struct ObserveSettings: View {
    let model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { model.snapshot.isObserveOnly },
                                     set: { on in Task { await model.setObserveOnly(on) } })) {
                    Text("Observe only")
                }
                if let since = model.snapshot.observeSince {
                    LabeledContent("Observed so far", value: BaselineWeek(since: since, now: model.now).observedLine)
                }
                if let error = model.observeError {
                    SettingsError(message: error)
                }
            }
            Section("Last 7 days") {
                ForEach(model.weeklySummary?.lines ?? [], id: \.label) { line in
                    LabeledContent(line.label, value: line.value)
                        // "median 44 seconds", not "44 s" (#66's approach).
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(line.label), \(line.spoken)")
                }
            }
        }
        .formStyle(.grouped)
        .task { await model.loadWeeklySummary() }
    }
}
