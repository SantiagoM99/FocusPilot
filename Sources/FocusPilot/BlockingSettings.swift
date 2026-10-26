import FocusPilotCore
import SwiftUI

/// Settings › Blocking: the RuleTable of blocked sites and apps, and the
/// compiled policy the extensions receive.
struct BlockingSettings: View {
    let model: AppModel
    @State private var selection: Int64?
    @State private var editing: RuleEditorSheet.Draft?
    @State private var excepting: SiteExceptionSheet.Draft?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                StrictRuleEditBanner(model: model)
                SectionHeader("Blocked sites and apps", note: "Blocked immediately, no check-in")
                VStack(spacing: 0) {
                    RuleTable(model: model, selection: $selection, edit: { editing = .init($0) },
                              except: { site in excepting = .init(site: site) })
                        .frame(minHeight: 200)
                    Divider()
                    HStack(spacing: 4) {
                        Button("Add Rule", systemImage: "plus") { editing = .init() }
                        Button("Remove Rule", systemImage: "minus") {
                            if let selection { Task { await model.deleteRuleSet(selection) } }
                        }
                        .disabled(selection == nil)
                        Spacer()
                        Button("Timed Exception…") {
                            if let site = selectedSite { excepting = .init(site: site) }
                        }
                        .labelStyle(.titleOnly)
                        .disabled(selectedSite == nil)
                        .help("Allow a blocked site or one of its pages for 5, 10 or 20 minutes")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .padding(6)
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                SettingsError(message: model.rulesError)
                ChromeSection(model: model)
                PolicyDebugView(policy: model.snapshot.policy)
            }
            .padding(20)
        }
        .sheet(item: $editing) { draft in
            RuleEditorSheet(model: model, draft: draft)
        }
        .sheet(item: $excepting) { draft in
            SiteExceptionSheet(model: model, draft: draft)
        }
    }

    /// The first site of the selected rule, if it blocks any.
    private var selectedSite: String? {
        model.ruleSets.first { $0.id == selection }?.firstSite
    }
}

extension BlockRuleSet {
    var firstSite: String? {
        targets.lazy.compactMap { if case .site(let domain) = $0 { domain } else { nil } }.first
    }
}

/// "Blocked sites and apps  Blocked immediately, no check-in".
struct SectionHeader: View {
    let title: String
    let note: String?

    init(_ title: String, note: String? = nil) {
        self.title = title
        self.note = note
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.headline)
            if let note {
                Text(note).font(.subheadline).foregroundStyle(.tertiary)
            }
        }
    }
}

/// Site or app, activation popup, status (design 07, RuleTable).
struct RuleTable: View {
    let model: AppModel
    @Binding var selection: Int64?
    let edit: (BlockRuleSet) -> Void
    /// Opens the timed exception sheet for a site.
    let except: (String) -> Void

    var body: some View {
        Table(model.ruleSets.map(RuleRow.init), selection: $selection) {
            TableColumn("Site or app") { (row: RuleRow) in
                let rule = row.rule
                VStack(alignment: .leading, spacing: 1) {
                    Text(rule.targets.map(\.displayName).joined(separator: ", "))
                    if let detail = detail(rule) {
                        Text(detail).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 3)
            }
            TableColumn("Activation") { (row: RuleRow) in
                ActivationMenu(rule: row.rule, model: model, edit: edit)
            }
            .width(140)
            TableColumn("Status") { (row: RuleRow) in
                Text(RuleText.status(row.rule, at: model.now, sessionRulesApply: model.snapshot.sessionRulesApply,
                                     exceptions: model.snapshot.policy?.exceptions ?? []))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 150)
        }
        .contextMenu(forSelectionType: Int64.self) { ids in
            if let rule = rule(ids.first) {
                Button("Edit…") { edit(rule) }
                if let site = rule.firstSite {
                    Button("Timed Exception…") { except(site) }
                }
                Button("Remove") { Task { await model.deleteRuleSet(rule.id!) } }
            }
        } primaryAction: { ids in
            if let rule = rule(ids.first) { edit(rule) }
        }
        .overlay {
            if model.ruleSets.isEmpty {
                Text("No blocked sites or apps yet. Press + to add one.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func rule(_ id: Int64?) -> BlockRuleSet? {
        model.ruleSets.first { $0.id == id }
    }

    /// The schedule, and for apps that hiding them needs the app running.
    private func detail(_ rule: BlockRuleSet) -> String? {
        var parts: [String] = []
        if case .schedule(let schedule) = rule.activation { parts.append(RuleText.summary(schedule)) }
        if rule.targets.contains(where: { if case .app = $0 { true } else { false } }) {
            parts.append("Requires FocusPilot running")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A saved rule set, identified by its database id.
private struct RuleRow: Identifiable {
    let rule: BlockRuleSet
    var id: Int64 { rule.id ?? -1 }
}

/// The Activation popup: Always and Session only apply at once; Schedule
/// opens the editor to pick days and times.
private struct ActivationMenu: View {
    let rule: BlockRuleSet
    let model: AppModel
    let edit: (BlockRuleSet) -> Void

    var body: some View {
        Menu(RuleText.activationName(rule.activation)) {
            Button("Always") { set(.always) }
            Button("Session only") { set(.sessionOnly) }
            Button("Schedule…") {
                var scheduled = rule
                if case .schedule = rule.activation {} else { scheduled.activation = .schedule(.workdays) }
                edit(scheduled)
            }
        }
        .menuStyle(.button)
        .fixedSize()
    }

    private func set(_ activation: RuleActivation) {
        var changed = rule
        changed.activation = activation
        Task { await model.save(changed) }
    }
}

extension WeeklySchedule {
    /// Mon–Fri 08:00–18:00 in the Mac's time zone: the starting point for a new schedule.
    static var workdays: WeeklySchedule {
        WeeklySchedule(days: [.mon, .tue, .wed, .thu, .fri], from: ClockTime(8, 0), to: ClockTime(18, 0), timeZone: .current)
    }
}
