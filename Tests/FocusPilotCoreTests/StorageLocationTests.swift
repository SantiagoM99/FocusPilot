import Foundation
import Testing
@testable import FocusPilotCore

@Suite("Storage location")
struct StorageLocationTests {
    @Test func defaultsToApplicationSupport() {
        let location = StorageLocation.applicationSupport(environment: [:])
        #expect(location.directory == URL.applicationSupportDirectory.appending(path: "FocusPilot", directoryHint: .isDirectory))
    }

    @Test func aDataDirectoryVariableReplacesItForTestsAndProbes() {
        let location = StorageLocation.applicationSupport(environment: ["FOCUSPILOT_DATA_DIR": "/tmp/fp-probe"])
        #expect(location.ownerDatabaseURL.path == "/tmp/fp-probe/FocusPilot.sqlite")
    }

    @Test func theCLISocketAndInboxLiveInAnOwnerOnlySubfolder() {
        let location = StorageLocation(directory: URL(fileURLWithPath: "/tmp/fp-probe"))
        #expect(location.commandSocketPath == "/tmp/fp-probe/CommandLine/cli.sock")
        #expect(location.inbox.fileURL.path == "/tmp/fp-probe/CommandLine/inbox.jsonl")
    }
}
