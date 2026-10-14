import Foundation

/// A clock the test moves by hand, so every instant the engine sees is explicit.
struct FakeClock {
    private(set) var now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    mutating func advance(minutes: Double) {
        now = now.addingTimeInterval(minutes * 60)
    }

    func minutes(from start: Date, _ minutes: Double) -> Date {
        start.addingTimeInterval(minutes * 60)
    }
}
