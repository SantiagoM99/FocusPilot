import Foundation

let bogota = TimeZone(identifier: "America/Bogota")!
let newYork = TimeZone(identifier: "America/New_York")!

/// An instant written as an ISO 8601 string with offset, e.g.
/// `"2026-10-14T10:00:00-05:00"`, so expectations read like the wall clock.
func instant(_ iso: String) -> Date {
    try! Date(iso, strategy: .iso8601)
}

/// Wednesday 14 October 2026, 10:00 in Bogotá: the fixed "now" for most tests.
let wednesdayMorningInBogota = instant("2026-10-14T10:00:00-05:00")
