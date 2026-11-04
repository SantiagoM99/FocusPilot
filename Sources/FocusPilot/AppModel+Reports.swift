import FocusPilotCore

/// Agent reports (#67). Accept is the only path that sends anything to an
/// agent, and it runs only for the owner's click on a report whose exact
/// message is on screen.
extension AppModel {
    /// Sends `shownMessage` to `shownTarget`, exactly as the row rendered them.
    func acceptReport(_ id: Int64, shownMessage: String, shownTarget: ReportTarget?) async {
        guard let coordinator else { return }
        switch await coordinator.acceptReport(id, shownMessage: shownMessage, shownTarget: shownTarget) {
        case .sent(let name):
            reportNotices[id] = nil
            agentNotice = "Sent to \(name)."
        case .outcomeUnknown:
            // The row shows the locked state from the report itself.
            reportNotices[id] = nil
        case .notSent(let refusal):
            reportNotices[id] = refusal.text
        }
        await refresh()
    }

    func dismissReport(_ id: Int64) async {
        reportNotices[id] = nil
        await perform("Could not dismiss the report") { try await $0.dismissReport(id) }
    }
}
