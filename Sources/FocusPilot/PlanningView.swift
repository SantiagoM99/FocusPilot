import AppKit
import FocusPilotCore
import SwiftUI

/// The planning window: Today's tasks and the quick capture sheet. The full
/// three-column layout arrives with the planning window ticket.
struct PlanningView: View {
    static let windowID = "planning"

    let model: AppModel
    @State private var isCapturing = false

    var body: some View {
        content
            .frame(minWidth: 480, minHeight: 320)
            .navigationTitle("Today")
            .navigationSubtitle(Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
            .toolbar {
                Button("New Task", systemImage: "plus") { isCapturing = true }
                    .keyboardShortcut("n")
                    .help("New task (⌘N)")
            }
            .sheet(isPresented: $isCapturing) {
                QuickCaptureSheet(model: model)
            }
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
        } else if model.today.isEmpty {
            ContentUnavailableView(
                "No tasks yet",
                systemImage: "sun.max",
                description: Text("Press ⌘N to capture one. Closing this window keeps FocusPilot running in the menu bar.")
            )
        } else {
            TodayList(items: model.today)
        }
    }
}
