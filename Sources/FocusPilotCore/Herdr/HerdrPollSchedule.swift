/// How long to wait before reading Herdr again: every 5 s while it answers,
/// doubling up to a minute while it or its binary is missing.
public struct HerdrPollSchedule: Sendable {
    static let connectedDelay = Duration.seconds(5)
    static let longestDelay = Duration.seconds(60)

    private var nextDisconnectedDelay = connectedDelay

    public init() {}

    public mutating func delay(after connection: HerdrConnection) -> Duration {
        guard case .disconnected = connection else {
            nextDisconnectedDelay = Self.connectedDelay
            return Self.connectedDelay
        }
        let delay = nextDisconnectedDelay
        nextDisconnectedDelay = min(delay * 2, Self.longestDelay)
        return delay
    }
}
