import FocusPilotCore
import SwiftUI

/// Adds or edits a block rule set: its sites and apps and when it blocks.
struct RuleEditorSheet: View {
    /// The rule being edited; a new one has no id.
    struct Draft: Identifiable {
        let id = UUID()
        var rule: BlockRuleSet

        init(_ rule: BlockRuleSet = BlockRuleSet(targets: [], activation: .always)) {
            self.rule = rule
        }
    }

    enum Kind: Hashable {
        case always, schedule, sessionOnly
    }

    let model: AppModel
    @State private var targets: [ActivityTarget]
    @State private var kind: Kind
    @State private var schedule: WeeklySchedule
    @State private var typedSite = ""
    @State private var siteError: String?
    /// Kept after adding a typed page, so the owner sees the whole domain was added.
    @State private var addedPageNote: String?
    @Environment(\.dismiss) private var dismiss
    private let original: BlockRuleSet

    init(model: AppModel, draft: Draft) {
        self.model = model
        original = draft.rule
        _targets = State(initialValue: draft.rule.targets)
        switch draft.rule.activation {
        case .always: _kind = State(initialValue: .always); _schedule = State(initialValue: .workdays)
        case .sessionOnly: _kind = State(initialValue: .sessionOnly); _schedule = State(initialValue: .workdays)
        case .schedule(let schedule): _kind = State(initialValue: .schedule); _schedule = State(initialValue: schedule)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(original.id == nil ? "Block Sites and Apps" : "Edit Rule")
                .font(.title3)
                .padding([.horizontal, .top], 20)
            Form {
                Section("Sites and apps") {
                    ForEach(targets, id: \.self) { target in
                        HStack {
                            Label(target.displayName, systemImage: icon(target))
                            Spacer()
                            Button("Remove", systemImage: "minus.circle") { targets.removeAll { $0 == target } }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                        }
                    }
                    HStack {
                        TextField("Site", text: $typedSite, prompt: Text("instagram.com"))
                            .onSubmit(addSite)
                        Button("Add Site", action: addSite)
                            .disabled(typedSite.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Add App…") {
                            if let app = AppPicker.choose(), !targets.contains(app) { targets.append(app) }
                        }
                    }
                    if let siteError {
                        Text(siteError).font(.callout).foregroundStyle(.orange)
                    } else if let note = RuleText.wholeDomainNote(typedSite) ?? addedPageNote {
                        Text(note).font(.callout).foregroundStyle(.orange)
                    } else {
                        Text("A site blocks the whole domain, subdomains included.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Section("When") {
                    Picker("Activation", selection: $kind) {
                        Text("Always").tag(Kind.always)
                        Text("On a schedule").tag(Kind.schedule)
                        Text("During focus sessions only").tag(Kind.sessionOnly)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    if kind == .schedule {
                        ScheduleEditor(schedule: $schedule)
                    }
                }
                SettingsError(message: model.rulesError)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { Task { if await model.save(rule) { dismiss() } } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(targets.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 520)
        .onAppear { model.rulesError = nil }
    }

    private var rule: BlockRuleSet {
        var rule = original
        rule.targets = targets
        switch kind {
        case .always: rule.activation = .always
        case .sessionOnly: rule.activation = .sessionOnly
        case .schedule: rule.activation = .schedule(schedule)
        }
        return rule
    }

    private func addSite() {
        guard let domain = SiteDomain.normalized(typedSite) else {
            siteError = "“\(typedSite)” isn't a site address."
            return
        }
        siteError = nil
        addedPageNote = RuleText.wholeDomainNote(typedSite)
        typedSite = ""
        if !targets.contains(.site(domain: domain)) { targets.append(.site(domain: domain)) }
    }

    private func icon(_ target: ActivityTarget) -> String {
        switch target {
        case .site: "globe"
        case .app: "app.dashed"
        case .tool: "terminal"
        }
    }
}

/// Days, from and to times, and the time zone of a schedule.
private struct ScheduleEditor: View {
    @Binding var schedule: WeeklySchedule

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Weekday.allCases, id: \.self) { day in
                Toggle(day.rawValue.capitalized, isOn: Binding(
                    get: { schedule.days.contains(day) },
                    set: { if $0 { schedule.days.insert(day) } else { schedule.days.remove(day) } }
                ))
                .toggleStyle(.button)
            }
        }
        DatePicker("From", selection: time(\.start), displayedComponents: .hourAndMinute)
            .environment(\.timeZone, schedule.timeZone)
        DatePicker("To", selection: time(\.end), displayedComponents: .hourAndMinute)
            .environment(\.timeZone, schedule.timeZone)
        if schedule.end < schedule.start {
            Text("Runs past midnight into the next day.").font(.callout).foregroundStyle(.secondary)
        }
        Picker("Time zone", selection: $schedule.timeZone) {
            ForEach(zones, id: \.self) { Text($0.identifier).tag($0) }
        }
    }

    private var zones: [TimeZone] {
        Array(Set([schedule.timeZone, .current])).sorted { $0.identifier < $1.identifier }
            + TimeZone.knownTimeZoneIdentifiers.compactMap(TimeZone.init(identifier:))
                .filter { $0 != schedule.timeZone && $0 != .current }
    }

    /// A Date binding for a ClockTime, read and written in the schedule's zone.
    private func time(_ keyPath: WritableKeyPath<WeeklySchedule, ClockTime>) -> Binding<Date> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = schedule.timeZone
        return Binding(
            get: {
                let value = schedule[keyPath: keyPath]
                return calendar.date(bySettingHour: value.hour, minute: value.minute, second: 0, of: .now) ?? .now
            },
            set: {
                let parts = calendar.dateComponents([.hour, .minute], from: $0)
                schedule[keyPath: keyPath] = ClockTime(parts.hour ?? 0, parts.minute ?? 0)
            }
        )
    }
}
