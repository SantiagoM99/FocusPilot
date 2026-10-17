import AppKit
import FocusPilotCore
import SwiftUI

/// The menu bar item itself. Its view exists for as long as the app runs, so
/// it also hosts the launch-time work that needs `openWindow`.
///
/// Keep this a plain image-and-text view: MenuBarExtra flattens its label, and
/// wrapping it in a TimelineView stopped the label's `.task` from running.
struct MenuBarIcon: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let status = model.menuBarStatus
        HStack(spacing: 4) {
            Image(nsImage: MenuBarGlyphImage.image(for: status.glyph))
            if let time = status.timeText {
                Text(time)
                    .monospacedDigit()
                    .foregroundStyle(status.isTimeDimmed ? .secondary : .primary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.accessibilityLabel)
        // Pause and Complete ask for a wrap-up, shown in the planning window.
        .onChange(of: model.planningWindowRequests) {
            openWindow(id: PlanningView.windowID)
            NSApplication.shared.activate()
        }
        .task {
            await model.refresh()
            if await model.claimPlanningWindowAtLaunch() {
                openWindow(id: PlanningView.windowID)
                NSApplication.shared.activate()
            }
        }
    }
}
