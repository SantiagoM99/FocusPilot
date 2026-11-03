import Foundation
import FocusPilotCore

/// In flight, the attention queue and Switch as the views use them (#57,
/// decision 0004). Both lists are worked out from what `refresh` loaded and
/// the current time; nothing here changes Now or opens an agent except
/// `confirmSwitch`, which runs only for the owner's click in the Switch sheet.
extension AppModel {
    var attention: [AttentionItem] {
        AttentionQueue.items(tasks: today, reviews: reviewItems, waiting: waiting, now: now)
    }

    var inFlight: [InFlightProject] {
        InFlight.projects(tasks: today, links: agentLinks, reviews: reviewItems, waiting: waiting, now: now)
    }

    func waiting(for taskID: Int64) -> TaskWaiting? {
        waiting.first { $0.taskID == taskID }
    }

    /// Opens the Switch sheet in the planning window; nothing changes yet.
    func requestSwitch(_ request: SwitchRequest) {
        switchRequest = request
        planningWindowRequests += 1
    }

    /// The owner confirmed Switch: the note, then Now, then the agent.
    func confirmSwitch(note: String) async {
        guard let request = switchRequest else { return }
        switchRequest = nil
        var opened: FocusCoordinator.OpenAgentResult?
        await perform("Could not switch") {
            opened = try await $0.switchTo(request.taskID, note: note, openingAgent: request.linkID, handling: request.item)
        }
        agentNotice = opened.flatMap(Self.notice)
    }

    func markWaiting(_ taskID: Int64, on: String, checkAt: Date?) async {
        await perform("Could not mark the task as waiting") { try await $0.markWaiting(taskID, on: on, checkAt: checkAt) }
    }

    func stopWaiting(_ taskID: Int64) async {
        await perform("Could not update the task") { try await $0.stopWaiting(taskID) }
    }

    func dismissCheck(_ taskID: Int64) async {
        await perform("Could not update the task") { try await $0.dismissCheck(taskID) }
    }
}
