import Foundation
@testable import FocusPilotCore

extension FocusSession {
    static let sampleStart = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// A 25-minute session started at `sampleStart`.
    static func sample(action: String = "Write the essay", phase: SessionPhase) -> FocusSession {
        FocusSession(
            id: UUID(), taskID: 1, action: action, mode: .normal,
            startedAt: sampleStart, plannedEnd: sampleStart.addingTimeInterval(25 * 60), phase: phase
        )
    }
}
