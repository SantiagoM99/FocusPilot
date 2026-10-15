import AppKit
import FocusPilotCore
import SwiftUI

/// Placeholder for the planning window; task capture and Today arrive in
/// later tickets.
struct PlanningView: View {
    static let windowID = "planning"

    let model: AppModel

    var body: some View {
        ContentUnavailableView(
            model.snapshot.statusText,
            systemImage: FocusSnapshot.fallbackSymbolName,
            description: Text("Closing this window keeps FocusPilot running in the menu bar.")
        )
        .frame(minWidth: 480, minHeight: 320)
        .task { await model.refresh() }
        // LSUIElement keeps the app out of the Dock, but while the planning
        // window is open the owner should be able to find it there and with
        // Command-Tab like any other window.
        .onAppear { NSApplication.shared.setActivationPolicy(.regular) }
        .onDisappear { NSApplication.shared.setActivationPolicy(.accessory) }
    }
}
