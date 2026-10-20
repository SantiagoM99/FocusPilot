import AppKit
import FocusPilotCore
import SwiftUI

/// The planning window (design 01, 07, 15 and 16): a sidebar with Today,
/// Projects, Review queue and Settings, and the quick capture sheet. A
/// selected task shows its Agent section in the inspector; the rest of the
/// task detail pane and protection status arrive with their tickets.
struct PlanningView: View {
    static let windowID = "planning"

    enum Page: Hashable {
        case today, projects, review, settings
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
                Label("Review queue", systemImage: "tray.full").tag(Page.review)
                    .badge(model.reviewItems.count)
                Label("Settings", systemImage: "gearshape").tag(Page.settings)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            content
                .navigationTitle(title)
                .navigationSubtitle(subtitle)
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

    private var title: String {
        switch page {
        case .projects: "Projects"
        case .review: "Review queue"
        case .settings: "Settings"
        case .today, nil: "Today"
        }
    }

    private var subtitle: String {
        switch page {
        case .projects, .settings: return ""
        case .review:
            let count = model.reviewItems.count
            let approvals = model.reviewItems.filter { $0.kind == .approval }.count
            let results = count == 1 ? "1 result" : "\(count) results"
            return count == 0 ? "Nothing queued"
                : approvals == 0 ? results : "\(results) · \(approvals) need\(approvals == 1 ? "s" : "") your approval"
        case .today, nil: return Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
    }

    @ViewBuilder private var content: some View {
        if let startupError = model.startupError {
            ContentUnavailableView("Database unavailable", systemImage: "exclamationmark.triangle", description: Text(startupError))
        } else if page == .projects {
            ProjectsView(model: model, showReviewQueue: { page = .review })
        } else if page == .review {
            ReviewQueueView(model: model)
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
                .taskInspector(model: model, items: model.today, selection: $todaySelection,
                               showReviewQueue: { page = .review })
        }
    }
}

extension View {
    /// The selected task's Agent section in an inspector, open while a task
    /// is selected.
    func taskInspector(model: AppModel, items: [TodayItem], selection: Binding<Int64?>,
                       showReviewQueue: @escaping () -> Void) -> some View {
        inspector(isPresented: Binding(get: { selection.wrappedValue != nil },
                                       set: { if !$0 { selection.wrappedValue = nil } })) {
            if let task = items.first(where: { $0.id == selection.wrappedValue }) {
                TaskAgentInspector(model: model, task: task, showReviewQueue: showReviewQueue)
                    .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
            }
        }
    }
}
