import AppKit
import FocusPilotCore

/// Blocked Mac apps and timed exceptions as the app uses them. `AppBlocker`
/// hides apps; this asks the coordinator for exceptions.
extension AppModel {
    /// Asks for a timed exception. Returns nil, with `exceptionError` set, if it was refused.
    func requestException(_ scope: ExceptionScope, duration: TimeInterval, reason: String,
                          confirmed: Bool) async -> ExceptionOutcome? {
        guard let coordinator else { return nil }
        do {
            let outcome = try await coordinator.requestException(scope, duration: duration, reason: reason, confirmed: confirmed)
            exceptionError = nil
            return outcome
        } catch ExceptionError.reasonRequired {
            exceptionError = "Say why you need it for the task."
        } catch {
            exceptionError = "Could not allow it: \(error.localizedDescription)"
        }
        return nil
    }

    func cancelException() async {
        await coordinator?.cancelException()
    }

    /// The Apps line of protection status (design 01, 03, 04).
    var appProtection: AppProtectionText {
        AppProtectionText(rules: ruleSets, policy: snapshot.policy, at: now)
    }
}
