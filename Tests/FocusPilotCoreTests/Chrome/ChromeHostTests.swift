import Foundation
import Synchronization
import Testing
@testable import FocusPilotCore

/// A value the host's closures and the test share.
final class Locked<Value: Sendable>: Sendable {
    private let mutex: Mutex<Value>
    init(_ value: Value) { mutex = Mutex(value) }
    func withLock<R>(_ body: (inout Value) -> R) -> R { mutex.withLock { body(&$0) } }
}

/// A host over a temporary data folder that records what it sends.
final class HostHarness {
    let location: StorageLocation
    let clock = SettableClock(wednesdayMorningInBogota)
    let appRunning = Locked(true)
    let opened = Locked(0)
    let frames = Locked<[Data]>([])
    let host: ChromeHost

    init() throws {
        location = StorageLocation(directory: try makeTemporaryDirectory())
        let (clock, appRunning, opened, frames) = (clock, appRunning, opened, frames)
        host = ChromeHost(location: location, environment: ChromeHost.Environment(
            isAppRunning: { appRunning.withLock { $0 } },
            openApp: { opened.withLock { $0 += 1 } },
            now: { clock.now },
            processID: 4242,
            send: { data in frames.withLock { $0.append(data) } }))
    }

    var sent: [[String: Any]] {
        frames.withLock { $0 }.map { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] ?? [:] }
    }

    func sent(_ type: String) -> [[String: Any]] {
        sent.filter { $0["type"] as? String == type }
    }

    func receive(_ object: [String: Any]) {
        host.receive(try! JSONSerialization.data(withJSONObject: object))
    }

    static let profile = "4F5CE721-0000-4000-8000-000000000001"

    func hello(incognito: Bool = false, allSites: Bool = true) {
        receive(["type": "hello", "profileId": Self.profile, "extensionId": ChromeExtension.id, "version": "1.0.0",
                 "incognitoAllowed": incognito, "allSitesAccess": allSites])
    }

    func observe(_ seq: Int, _ kind: String, _ extra: [String: Any] = [:]) {
        receive(["type": "observation", "seq": seq, "profileId": Self.profile, "kind": kind,
                 "observedAt": "2026-10-14T15:00:00Z"].merging(extra) { a, _ in a })
    }

    func publish(revision: Int, source: String? = nil) async {
        let rules = PolicyCompiler.compile(rules: [BlockRuleSet(id: 1, targets: [.site(domain: "youtube.com")], activation: .always)],
                                           allowed: [], session: nil)
        await ChromePolicyMailbox(location: location).publish(
            PolicyDelivery(policy: CompiledPolicy(revision: revision, effectiveAt: clock.now, rules: rules), focus: nil, source: source))
    }

    func record() throws -> ChromeProfileRecord? {
        try ChromeProfileStore(location: location).record(HostHarness.profile)
    }
}

@Suite("Chrome native host")
struct ChromeHostTests {
    @Test func onlyTheFocusPilotExtensionIsAccepted() {
        #expect(ChromeHost.accepts(origin: "chrome-extension://\(ChromeExtension.id)/"))
        #expect(!ChromeHost.accepts(origin: "chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/"))
        #expect(!ChromeHost.accepts(origin: ""))
    }

    @Test func helloGetsTheCurrentPolicyAndWhetherTheAppRuns() async throws {
        let harness = try HostHarness()
        await harness.publish(revision: 7)

        harness.hello()

        let policy = try #require(harness.sent("policy").last)
        #expect((policy["policy"] as? [String: Any])?["revision"] as? Int == 7)
        #expect(harness.sent("status").last?["appRunning"] as? Bool == true)
    }

    // An app update refreshes the extension folder; the extension reloads
    // itself when the build there differs from the one it runs.
    @Test func theStatusNamesTheExtensionBuildOnDisk() throws {
        let harness = try HostHarness()
        try FileManager.default.createDirectory(at: harness.location.chromeExtensionDirectory, withIntermediateDirectories: true)
        try Data(#"{"version":"1.0.0","version_name":"1.0.0 build 3f2a"}"#.utf8)
            .write(to: harness.location.chromeExtensionDirectory.appending(path: "manifest.json"))

        harness.hello()

        #expect(harness.sent("status").last?["extensionBuild"] as? String == "1.0.0 build 3f2a")
    }

    // The app copies a new build into the folder after it starts listening,
    // so a host can say hello before the copy lands.
    @Test func aNewBuildOnDiskIsReportedWhenItLands() throws {
        let harness = try HostHarness()
        let folder = harness.location.chromeExtensionDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest = folder.appending(path: "manifest.json")
        try Data(#"{"version_name":"1.0.0 build aaaa"}"#.utf8).write(to: manifest)
        harness.hello()

        harness.host.poll()
        try Data(#"{"version_name":"1.0.0 build bbbb"}"#.utf8).write(to: manifest)
        harness.host.poll()
        harness.host.poll()

        #expect(harness.sent("status").map { $0["extensionBuild"] as? String } == ["1.0.0 build aaaa", "1.0.0 build bbbb"])
    }

    @Test func aNewerPolicyIsPushedOnceWhenTheAppPublishesIt() async throws {
        let harness = try HostHarness()
        harness.hello()
        await harness.publish(revision: 8)

        harness.host.poll()
        harness.host.poll()

        #expect(harness.sent("policy").count == 1)
    }

    @Test func aPolicyFromAnotherDatabaseIsPushedWhateverItsRevision() async throws {
        let harness = try HostHarness()
        await harness.publish(revision: 50, source: "A")
        harness.hello()
        await harness.publish(revision: 3, source: "B")

        harness.host.poll()

        let sent = harness.sent("policy").map { ($0["source"] as? String, ($0["policy"] as? [String: Any])?["revision"] as? Int) }
        #expect(sent.map(\.0) == ["A", "B"])
        #expect(sent.map(\.1) == [50, 3])
    }

    @Test func theAppStartingOrStoppingIsReported() throws {
        let harness = try HostHarness()
        harness.hello()
        harness.appRunning.withLock { $0 = false }

        harness.host.poll()
        harness.host.poll()

        #expect(harness.sent("status").map { $0["appRunning"] as? Bool } == [true, false])
    }

    @Test func observationsAreAcknowledgedOnlyAfterTheyAreRecorded() throws {
        let harness = try HostHarness()
        harness.hello()

        harness.observe(1, "worker-start")
        harness.observe(2, "blocked-shown")

        #expect(harness.sent("ack").map { $0["seq"] as? Int } == [1, 2])
        #expect(try harness.record()?.lastSeq == 2)
        #expect(try harness.record()?.blockedPagesShown == 1)
    }

    @Test func aResentObservationIsAcknowledgedAgainButCountedOnce() throws {
        let harness = try HostHarness()
        harness.observe(1, "blocked-shown")

        harness.observe(1, "blocked-shown")

        #expect(harness.sent("ack").count == 2)
        #expect(try harness.record()?.blockedPagesShown == 1)
    }

    @Test func gapsInTheSequenceAreRecorded() throws {
        let harness = try HostHarness()
        harness.observe(1, "worker-start")

        harness.observe(5, "worker-start")

        #expect(try harness.record()?.missingObservations == 3)
    }

    // A restarted worker can send its new observation before resending older
    // ones it never got acknowledged; those still count once they arrive.
    @Test func anObservationArrivingAfterALaterOneIsStillRecorded() throws {
        let harness = try HostHarness()
        harness.observe(1, "worker-start")
        harness.observe(3, "worker-start")

        harness.observe(2, "policy-applied", ["revision": 9, "checksum": "abc"])
        harness.observe(2, "policy-applied", ["revision": 9, "checksum": "abc"])

        #expect(harness.sent("ack").map { $0["seq"] as? Int } == [1, 3, 2, 2])
        #expect(try harness.record()?.appliedRevision == 9)
        #expect(try harness.record()?.missingObservations == 0)
        #expect(try harness.record()?.lastSeq == 3)
    }

    @Test func aLateBlockedPageIsCountedOnce() throws {
        let harness = try HostHarness()
        harness.observe(2, "worker-start")

        harness.observe(1, "blocked-shown")
        harness.observe(1, "blocked-shown")

        #expect(try harness.record()?.blockedPagesShown == 1)
    }

    @Test func aPolicyAppliedObservationIsTheProfilesAcknowledgement() throws {
        let harness = try HostHarness()

        harness.observe(1, "policy-applied", ["revision": 9, "checksum": "abc"])

        #expect(try harness.record()?.appliedRevision == 9)
        #expect(try harness.record()?.appliedChecksum == "abc")
    }

    @Test func anAcknowledgementFromAnotherDatabaseReplacesAHigherRevision() throws {
        let harness = try HostHarness()
        harness.observe(1, "policy-applied", ["revision": 50, "checksum": "old", "source": "A"])

        harness.observe(2, "policy-applied", ["revision": 3, "checksum": "new", "source": "B"])
        harness.observe(3, "policy-applied", ["revision": 2, "checksum": "stale", "source": "B"])

        #expect(try harness.record()?.appliedRevision == 3)
        #expect(try harness.record()?.appliedSource == "B")
        #expect(try harness.record()?.appliedChecksum == "new")
    }

    @Test func helloRecordsIncognitoAndSiteAccess() throws {
        let harness = try HostHarness()

        harness.hello(incognito: true, allSites: false)

        let record = try #require(try harness.record())
        #expect(record.incognitoAllowed)
        #expect(!record.allSitesAccess)
        #expect(record.hostProcessID == 4242)
    }

    @Test func profilesOutsideTheExpectedFormAreIgnored() throws {
        let harness = try HostHarness()

        harness.receive(["type": "observation", "seq": 1, "profileId": "../../evil", "kind": "x", "observedAt": "2026-10-14T15:00:00Z"])

        #expect(harness.sent("ack").isEmpty)
        #expect(try ChromeProfileStore(location: harness.location).records().isEmpty)
    }

    @Test func returnToTaskOpensTheApp() throws {
        let harness = try HostHarness()

        harness.receive(["type": "open-app"])

        #expect(harness.opened.withLock { $0 } == 1)
    }

    @Test func stoppingMarksTheProfileDisconnected() throws {
        let harness = try HostHarness()
        harness.hello()

        harness.host.stop()

        #expect(try harness.record()?.hostProcessID == nil)
    }
}

@Suite("Chrome profile status")
struct ChromeProfileStatusTests {
    @Test func eachProfileAcknowledgesSeparately() throws {
        let harness = try HostHarness()
        harness.hello()
        harness.observe(1, "policy-applied", ["revision": 9, "checksum": "abc"])
        let other = "4F5CE721-0000-4000-8000-000000000002"
        harness.receive(["type": "hello", "profileId": other, "extensionId": ChromeExtension.id, "version": "1.0.0",
                         "incognitoAllowed": false, "allSitesAccess": true])

        let statuses = try ChromeProfiles.statuses(location: harness.location, currentRevision: 9, isRunning: { _ in true })

        #expect(statuses.map(\.profileID).sorted() == [HostHarness.profile, other].sorted())
        #expect(statuses.first { $0.profileID == HostHarness.profile }?.state == .acknowledged(revision: 9))
        #expect(statuses.first { $0.profileID == other }?.state == .waiting)
    }

    @Test func aProfileWhoseHostExitedIsDisconnected() throws {
        let harness = try HostHarness()
        harness.hello()
        harness.observe(1, "policy-applied", ["revision": 9, "checksum": "abc"])

        let statuses = try ChromeProfiles.statuses(location: harness.location, currentRevision: 9, isRunning: { _ in false })

        #expect(statuses.first?.state == .disconnected(lastSeen: wednesdayMorningInBogota))
    }

    @Test func anOlderAcknowledgedRevisionIsStillSyncing() throws {
        let harness = try HostHarness()
        harness.hello()
        harness.observe(1, "policy-applied", ["revision": 8, "checksum": "abc"])

        let statuses = try ChromeProfiles.statuses(location: harness.location, currentRevision: 9, isRunning: { _ in true })

        #expect(statuses.first?.state == .syncing(acknowledged: 8))
    }

    @Test func anAcknowledgementFromAnotherDatabaseIsStillWaiting() throws {
        let harness = try HostHarness()
        harness.hello()
        harness.observe(1, "policy-applied", ["revision": 50, "checksum": "abc", "source": "A"])

        let statuses = try ChromeProfiles.statuses(location: harness.location, currentRevision: 3, currentSource: "B",
                                                   isRunning: { _ in true })

        #expect(statuses.first?.state == .waiting)
    }

    // One unreadable file must not hide every other profile in Settings.
    @Test func aCorruptRecordIsSkipped() throws {
        let harness = try HostHarness()
        harness.hello()
        let corrupt = harness.location.chromeProfilesDirectory.appending(path: "4F5CE721-0000-4000-8000-000000000009.json")
        try Data("{not json".utf8).write(to: corrupt)

        let statuses = try ChromeProfiles.statuses(location: harness.location, currentRevision: nil, isRunning: { _ in true })

        #expect(statuses.map(\.profileID) == [HostHarness.profile])
    }

    @Test func theOwnerCanForgetADisconnectedProfile() throws {
        let harness = try HostHarness()
        harness.hello()
        harness.observe(1, "worker-start")
        harness.host.stop()

        try ChromeProfiles.forget(HostHarness.profile, location: harness.location, isRunning: { _ in false })

        #expect(try harness.record() == nil)
        let left = try FileManager.default.contentsOfDirectory(atPath: harness.location.chromeProfilesDirectory.path)
        #expect(left.isEmpty)
    }

    @Test func aConnectedProfileIsNotForgotten() throws {
        let harness = try HostHarness()
        harness.hello()

        #expect(throws: ChromeProfiles.ForgetError.connected) {
            try ChromeProfiles.forget(HostHarness.profile, location: harness.location, isRunning: { _ in true })
        }
        #expect(try harness.record() != nil)
    }

    @Test func statusTextSaysWhatTheOwnerNeedsToKnow() {
        #expect(ChromeProfileStatus.text(.acknowledged(revision: 41)) == "Chrome has your latest rules")
        #expect(ChromeProfileStatus.text(.waiting) == "Connected · waiting for the policy")
        #expect(ChromeProfileStatus.text(.syncing(acknowledged: 40)) == "Chrome is updating…")
        #expect(ChromeProfileStatus.text(.disconnected(lastSeen: nil)) == "Disconnected")
    }
}
