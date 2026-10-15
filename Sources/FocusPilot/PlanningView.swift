import FocusPilotCore
import SwiftUI

/// Placeholder for the planning window; task capture and Today arrive in
/// later tickets.
struct PlanningView: View {
    static let windowID = "planning"

    let model: AppModel

    var body: some View {
        ContentUnavailableView(
            model.snapshot.menuBarTitle,
            systemImage: "scope",
            description: Text("Closing this window keeps FocusPilot running in the menu bar.")
        )
        .frame(minWidth: 480, minHeight: 320)
        .task { await model.refresh() }
    }
}
