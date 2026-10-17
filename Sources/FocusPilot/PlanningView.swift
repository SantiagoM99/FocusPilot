import AppKit
import FocusPilotCore
import SwiftUI

/// The planning window (design 01 and 15): a sidebar with Today and
/// Projects, and the quick capture sheet. The task detail pane, Review
/// queue and protection status arrive with their tickets.
struct PlanningView: View {
    static let windowID = "planning"

    enum Page: Hashable {
        case today, projects
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
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            content
                .navigationTitle(page == .projects ? "Projects" : "Today")
                .navigationSubtitle(page == .projects ? ""
                    : Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .toolbar {
                    Button("New Task", systemImage: "plus") { isCapturing = true }
                        .help("New task (⌘N)")
                }
        }
        .frame(minWidth: 760, minHeight: 420)
        .focusedSceneValue(\.quickCapture, { isCapturing = true })
        .sheet(isPresented: $isCapturing) {
            QuickCaptureSheet(model: model)
        }
        .sheet(isPresented: Bindable(model).isStartingFocus) {
            StartFocusSheet(model: model)
        }
        .environment(model)
        .task { await model.refresh() }
        // LSUIElement keeps the app out of the Dock, but while the planning
        // window is open the owner should be able to find it there and with
        // Command-Tab like any other window.
        .onAppear { NSApplication.shared.setActivationPolicy(.regular) }
        .onDisappear { NSApplication.shared.setActivationPolicy(.accessory) }
    }

    @ViewBuilder private var content: some View {
        if let startupError = model.startupError {
            ContentUnavailableView("Database unavailable", systemImage: "exclamationmark.triangle", description: Text(startupError))
        } else if page == .projects {
            ProjectsView(model: model)
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
                     selection: $todaySelection)
        }
    }
}
