import AppKit
import FocusPilotCore
import SwiftUI

/// The planning window (design 01, 07 and 15): a sidebar with Today,
/// Projects and Settings, and the quick capture sheet. The task detail pane, Review
/// queue and protection status arrive with their tickets.
struct PlanningView: View {
    static let windowID = "planning"

    enum Page: Hashable {
        case today, projects, settings
    }

    let model: AppModel
    @State private var page: Page?
    @State private var isCapturing = false
    @State private var todaySelection: Int64?

    init(model: AppModel, page: Page = .today) {
        self.model = model
        _page = State(initialValue: page)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                Label("Today", systemImage: "sun.max").tag(Page.today)
                Label("Projects", systemImage: "folder").tag(Page.projects)
                Label("Settings", systemImage: "gearshape").tag(Page.settings)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            content
                .navigationTitle(title)
                .navigationSubtitle(page != .today ? ""
                    : Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .toolbar {
                    Button("New Task", systemImage: "plus") { isCapturing = true }
                        .help("New task (⌘N)")
                }
        }
        .frame(minWidth: 760, minHeight: 420)
        .focusedSceneValue(\.quickCapture, { isCapturing = true })
        .sheet(item: sheet) { sheet in
            switch sheet {
            case .capture: QuickCaptureSheet(model: model)
            case .startFocus: StartFocusSheet(model: model)
            case .wrapUp:
                if let pending = model.wrapUp { WrapUpSheet(model: model, prompt: pending.prompt) }
            }
        }
        .environment(model)
        .task { await model.refresh() }
        .onChange(of: model.requestedPage, initial: true) {
            if let requested = model.requestedPage {
                page = requested
                model.requestedPage = nil
            }
        }
        // LSUIElement keeps the app out of the Dock, but while the planning
        // window is open the owner should be able to find it there and with
        // Command-Tab like any other window.
        .onAppear { NSApplication.shared.setActivationPolicy(.regular) }
        .onDisappear { NSApplication.shared.setActivationPolicy(.accessory) }
    }

    /// One sheet modifier, so a wrap-up and Start focus wanted at once show
    /// one after the other instead of one being dropped (see `PlanningSheet`).
    /// Closing a sheet clears only what that sheet was showing.
    private var sheet: Binding<PlanningSheet?> {
        Binding(
            get: { PlanningSheet.showing(isCapturing: isCapturing, wrapUp: model.wrapUp, isStartingFocus: model.isStartingFocus) },
            set: { newValue in
                guard newValue == nil else { return }
                switch PlanningSheet.showing(isCapturing: isCapturing, wrapUp: model.wrapUp, isStartingFocus: model.isStartingFocus) {
                case .capture: isCapturing = false
                case .wrapUp: model.skipWrapUp()
                case .startFocus: model.isStartingFocus = false
                case nil: break
                }
            }
        )
    }

    private var title: String {
        switch page {
        case .projects: "Projects"
        case .settings: "Settings"
        case .today, nil: "Today"
        }
    }

    @ViewBuilder private var content: some View {
        if let startupError = model.startupError {
            ContentUnavailableView("Database unavailable", systemImage: "exclamationmark.triangle", description: Text(startupError))
        } else if page == .projects {
            ProjectsView(model: model)
        } else if page == .settings {
            SettingsPage(model: model)
        } else if model.today.isEmpty {
            ContentUnavailableView(
                "No tasks yet",
                systemImage: "sun.max",
                description: Text("Press ⌘N to capture one. Closing this window keeps FocusPilot running in the menu bar.")
            )
        } else {
            TaskList(items: model.today, showsProject: true,
                     move: { id, status, placement in Task { await model.move(id, to: status, placement) } },
                     undoHerdrAdd: { id in Task { await model.undoHerdrAdd(id) } },
                     activeSessionTaskID: model.snapshot.activeSession?.taskID,
                     selection: $todaySelection)
        }
    }
}
