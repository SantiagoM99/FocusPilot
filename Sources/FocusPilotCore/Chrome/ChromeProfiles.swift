import Foundation

/// One Chrome profile's protection, as the app reports it.
public struct ChromeProfileStatus: Equatable, Sendable, Identifiable {
    public enum State: Equatable, Sendable {
        /// Applied the current policy.
        case acknowledged(revision: Int)
        /// Connected, applied an older one; the newer one is on its way.
        case syncing(acknowledged: Int)
        /// Connected, nothing applied yet.
        case waiting
        /// No host is running for the profile, e.g. Chrome is closed.
        case disconnected(lastSeen: Date?)
    }

    public var profileID: String
    public var state: State
    public var incognitoAllowed: Bool
    public var allSitesAccess: Bool
    public var missingObservations: Int
    public var id: String { profileID }

    public static func text(_ state: State) -> String {
        switch state {
        case .acknowledged(let revision): "Connected · policy rev. \(revision) acknowledged"
        case .syncing(let acknowledged): "Syncing · rev. \(acknowledged) acknowledged"
        case .waiting: "Connected · waiting for the policy"
        case .disconnected: "Disconnected"
        }
    }
}

public enum ChromeProfiles {
    /// Each profile against the current revision. `isRunning` checks whether
    /// a host process still exists, since a crashed host cannot say it stopped.
    public static func statuses(location: StorageLocation, currentRevision: Int?,
                                isRunning: (Int32) -> Bool = processExists) throws -> [ChromeProfileStatus] {
        try ChromeProfileStore(location: location).records()
            .sorted { $0.lastSeenAt > $1.lastSeenAt }
            .map { record in
                ChromeProfileStatus(profileID: record.profileID, state: state(record, currentRevision, isRunning),
                                    incognitoAllowed: record.incognitoAllowed, allSitesAccess: record.allSitesAccess,
                                    missingObservations: record.missingObservations)
            }
    }

    private static func state(_ record: ChromeProfileRecord, _ current: Int?, _ isRunning: (Int32) -> Bool) -> ChromeProfileStatus.State {
        guard let pid = record.hostProcessID, isRunning(pid) else { return .disconnected(lastSeen: record.lastSeenAt) }
        guard let applied = record.appliedRevision else { return .waiting }
        if let current, applied < current { return .syncing(acknowledged: applied) }
        return .acknowledged(revision: applied)
    }

    public static func processExists(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
