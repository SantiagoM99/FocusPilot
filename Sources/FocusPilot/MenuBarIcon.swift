import AppKit
import FocusPilotCore
import SwiftUI

/// The menu bar item itself. Its view exists for as long as the app runs, so
/// it also hosts the launch-time work that needs `openWindow`.
struct MenuBarIcon: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: FocusSnapshot.menuBarSymbolName)
            .accessibilityLabel(model.snapshot.menuBarAccessibilityLabel)
            .task {
                await model.refresh()
                if await model.claimPlanningWindowAtLaunch() {
                    openWindow(id: PlanningView.windowID)
                    NSApplication.shared.activate()
                }
            }
    }
}
