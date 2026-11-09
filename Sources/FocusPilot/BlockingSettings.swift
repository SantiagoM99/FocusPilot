import FocusPilotCore
import SwiftUI

/// Settings › Blocking (redesign Settings.dc.html): the blocked sites, blocked
/// apps and always-allowed lists, and what sessions start with.
struct BlockingSettings: View {
    let model: AppModel
    @State private var editing: RuleEditorSheet.Draft?
    @State private var excepting: SiteExceptionSheet.Draft?
    @State private var isAllowingSite = false

    var body: some View {
        let lists = BlockingLists(rules: model.ruleSets, allowed: model.allowed, at: model.now,
                                  exceptions: model.snapshot.policy?.exceptions ?? [])
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                StrictRuleEditBanner(model: model)
                HStack(alignment: .top, spacing: 28) {
                    SettingsListSection("BLOCKED SITES", empty: "No blocked sites", rows: lists.sites) {
                        AddButton(label: "Add blocked site") { editing = .init() }
                    } row: { blockedRow($0) }
                    SettingsListSection("BLOCKED APPS", empty: "No blocked apps", rows: lists.apps) {
                        AddButton(label: "Add blocked app", action: addBlockedApp)
                    } row: { blockedRow($0) }
                }
                HStack(alignment: .top, spacing: 28) {
                    SettingsListSection("ALWAYS ALLOWED", empty: "Nothing allowed", rows: lists.allowed) {
                        addAllowedMenu
                    } row: { allowedRow($0) }
                    SessionsSection(model: model)
                }
                SettingsError(message: model.rulesError)
            }
            .padding(24)
        }
        .sheet(item: $editing) { RuleEditorSheet(model: model, draft: $0) }
        .sheet(item: $excepting) { SiteExceptionSheet(model: model, draft: $0) }
        .sheet(isPresented: $isAllowingSite) { AllowSiteSheet(model: model) }
    }

    private func addBlockedApp() {
        if let app = AppPicker.choose() {
            editing = .init(BlockRuleSet(targets: [app], activation: .always))
        }
    }

    private var addAllowedMenu: some View {
        Menu {
            Button("Add Site…") { isAllowingSite = true }
            Button("Add App…") {
                if let app = AppPicker.choose() {
                    Task { await model.allow(AllowedActivity(name: app.displayName, target: app)) }
                }
            }
        } label: {
            AddButtonLabel()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Add allowed app or site")
    }

    @ViewBuilder
    private func blockedRow(_ row: BlockingRow) -> some View {
        if case .rule(let rule) = row.source {
            let site = row.target.siteDomain
            let remove = { Task { await model.remove(row.target, from: rule) }; return }
            let edit = { editing = .init(rule) }
            TargetRow(row: row, edit: edit, remove: remove) {
                Button("Edit…", action: edit)
                if let site {
                    Button("Timed Exception…") { excepting = .init(site: site) }
                }
                Button("Remove", action: remove)
            }
        }
    }

    @ViewBuilder
    private func allowedRow(_ row: BlockingRow) -> some View {
        if case .allowed(let id) = row.source {
            let remove = { Task { await model.removeAllowed(id) }; return }
            TargetRow(row: row, edit: nil, remove: remove) {
                Button("Remove", action: remove)
            }
        }
    }
}

extension ActivityTarget {
    var siteDomain: String? {
        if case .site(let domain) = self { domain } else { nil }
    }
}

/// A small-caps section label, as the boards draw them.
struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .kerning(0.88)
            .foregroundStyle(.palette(.secondaryText))
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 4)
    }
}

/// The bordered list the Settings tabs group their rows in.
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.palette(.separator)))
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(Color.palette(.separator)).frame(height: 1)
    }
}

private struct SettingsListSection<Add: View, Row: View>: View {
    let title: String
    let empty: String
    let rows: [BlockingRow]
    @ViewBuilder let add: Add
    @ViewBuilder let row: (BlockingRow) -> Row

    init(_ title: String, empty: String, rows: [BlockingRow], @ViewBuilder add: () -> Add,
         @ViewBuilder row: @escaping (BlockingRow) -> Row) {
        self.title = title
        self.empty = empty
        self.rows = rows
        self.add = add()
        self.row = row
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title)
                Spacer()
                add
            }
            .padding(.trailing, 4)
            SettingsCard {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { SettingsDivider() }
                    row(item)
                }
                if rows.isEmpty {
                    Text(empty)
                        .font(.system(size: 13))
                        .foregroundStyle(.palette(.secondaryText))
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .padding(.horizontal, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AddButtonLabel: View {
    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.palette(.text))
            .frame(width: 24, height: 24)
            .background(Color.palette(.buttonBackground), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.palette(.buttonBorder)))
            .contentShape(Rectangle())
    }
}

private struct AddButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { AddButtonLabel() }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }
}

/// A target and its activation or kind. Clicking opens its rule; a remove
/// control appears on hover, and the context menu has the rest.
private struct TargetRow<Menu: View>: View {
    let row: BlockingRow
    let edit: (() -> Void)?
    let remove: () -> Void
    @ViewBuilder let menu: Menu
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Text(row.title)
                .font(.system(size: 13))
                .foregroundStyle(.palette(.text))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.detail)
                .font(.system(size: 12))
                .foregroundStyle(.palette(.secondaryText))
                .lineLimit(1)
            if isHovering {
                Button("Remove", systemImage: "minus.circle", action: remove)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { edit?() }
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Remove", remove)
        .modifier(EditAction(edit: edit))
    }
}

private struct EditAction: ViewModifier {
    let edit: (() -> Void)?

    func body(content: Content) -> some View {
        if let edit {
            content.accessibilityAction(named: "Edit", edit)
        } else {
            content
        }
    }
}

/// Default length, Strict by default and the floating panel.
private struct SessionsSection: View {
    let model: AppModel

    var body: some View {
        @Bindable var sessions = model.sessionPreferences
        @Bindable var panel = model.menuBarPreferences
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("SESSIONS")
                .frame(height: 24)
            SettingsCard {
                row("Default length") {
                    Picker("Default length", selection: $sessions.defaultMinutes) {
                        ForEach(SessionPreferences.lengths, id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                row("Strict by default") {
                    Toggle("Strict by default", isOn: $sessions.strictByDefault)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsDivider()
                row("Floating panel") {
                    Toggle("Floating panel", isOn: $panel.showsFocusPanel)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: panel.showsFocusPanel) { model.focusPanel.update() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ title: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.palette(.text))
            Spacer()
            control().controlSize(.small)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }
}

extension WeeklySchedule {
    /// Mon–Fri 08:00–18:00 in the Mac's time zone: the starting point for a new schedule.
    static var workdays: WeeklySchedule {
        WeeklySchedule(days: [.mon, .tue, .wed, .thu, .fri], from: ClockTime(8, 0), to: ClockTime(18, 0), timeZone: .current)
    }
}
