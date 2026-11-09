import AppKit
import FocusPilotCore
import SwiftUI

/// The planning window (redesign 2026-11, Main; #70): a sidebar with Today,
/// In flight, Projects, Review queue and Settings and a one-line protection
/// footer, a header with the page title, the date on Today and New Task,
/// and the quick capture sheet. A selected task shows its Agent section in
/// the inspector. Colors come from `Palette`.
struct PlanningView: View {
    static let windowID = "planning"

    typealias Page = PlanningPage

    let model: AppModel
    @State private var page: Page?
    @State private var isCapturing = false
    @State private var todaySelection: Int64?

    init(model: AppModel, page: Page = .today) {
        self.model = model
        _page = State(initialValue: page)
    }

    var body: some View {
        // A fixed sidebar beside the page, as the board draws it: the window's
        // buttons sit over the sidebar and the header is level with them.
        HStack(spacing: 0) {
            PlanningSidebar(model: model, page: $page)
                .frame(width: 210)
                .overlay(alignment: .trailing) { Rectangle().fill(Color.palette(.sidebarBorder)).frame(width: 1) }
            VStack(spacing: 0) {
                // The date is read each minute, so it turns over at midnight.
                TimelineView(.everyMinute) { context in
                    PlanningHeader(title: title, date: page == .today || page == nil ? PageHeader.todayDate(context.date) : nil,
                                   newTask: { isCapturing = true })
                }
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.palette(.window))
        }
        .ignoresSafeArea(.container, edges: .top)
        .navigationTitle(title)
        .frame(minWidth: 760, minHeight: 420)
        .focusedSceneValue(\.quickCapture, { isCapturing = true })
        .sheet(item: sheet) { sheet in
            switch sheet {
            case .capture: QuickCaptureSheet(model: model)
            case .startFocus: StartFocusSheet(model: model)
            case .wrapUp:
                if let pending = model.wrapUp { WrapUpSheet(model: model, prompt: pending.prompt) }
            case .switchTask:
                if let request = model.switchRequest { SwitchSheet(model: model, request: request) }
            case .markWaiting(let taskID):
                MarkWaitingSheet(model: model, taskID: taskID)
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
    /// Closing a sheet clears only what that sheet was showing. A wrap-up is
    /// never dropped this way: only Skip and Save end it, so its draft stays.
    private var sheet: Binding<PlanningSheet?> {
        Binding(
            get: { showing },
            set: { newValue in
                guard newValue == nil else { return }
                switch showing {
                case .capture: isCapturing = false
                case .wrapUp: break
                case .switchTask: model.switchRequest = nil
                case .markWaiting: model.markingWaiting = nil
                case .startFocus: model.isStartingFocus = false
                case nil: break
                }
            }
        )
    }

    private var showing: PlanningSheet? {
        PlanningSheet.showing(isCapturing: isCapturing, wrapUp: model.wrapUp, isStartingFocus: model.isStartingFocus,
                              switching: model.switchRequest, markingWaiting: model.markingWaiting)
    }

    private var title: String {
        switch page {
        case .inFlight: "In flight"
        case .projects: "Projects"
        case .review: "Review queue"
        case .settings: "Settings"
        case .today, nil: "Today"
        }
    }

    @ViewBuilder private var content: some View {
        if let startupError = model.startupError {
            ContentUnavailableView("Database unavailable", systemImage: "exclamationmark.triangle", description: Text(startupError))
        } else if page == .projects {
            ProjectsView(model: model, showReviewQueue: { page = .review })
        } else if page == .inFlight {
            InFlightView(model: model)
        } else if page == .review {
            ReviewQueueView(model: model)
        } else if page == .settings {
            SettingsPage(model: model)
        } else if model.today.isEmpty {
            ContentUnavailableView("No tasks yet", systemImage: "sun.max")
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
