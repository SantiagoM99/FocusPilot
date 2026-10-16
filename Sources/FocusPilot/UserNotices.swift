import FocusPilotCore
import UserNotifications

/// Tells the owner when a session reaches its planned end or a break ends.
/// Authorization is provisional: notices arrive quietly in Notification
/// Center without a permission prompt, until the owner decides otherwise.
struct UserNotices: FocusNoticeSink {
    func deliver(_ notice: FocusNotice) async {
        // Notification Center needs an app bundle; a bare debug binary has none.
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .provisional])
        let content = UNMutableNotificationContent()
        switch notice {
        case .sessionReachedPlannedEnd:
            content.title = "Focus session ended"
            content.body = "You reached the planned end."
        case .breakEnded:
            content.title = "Break is over"
            content.body = "Back to your focus session."
        }
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
