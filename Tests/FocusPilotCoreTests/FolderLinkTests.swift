import Foundation
import Testing
@testable import FocusPilotCore

/// Real folders in a temporary directory; the Trash is a folder named
/// `.Trash` there, so nothing reaches the owner's own Trash.
private struct Folders {
    let base: URL
    let access = SystemFolderAccess()

    init() throws {
        base = URL(fileURLWithPath: FolderContainment.canonical(try makeTemporaryDirectory().path)!)
    }

    @discardableResult
    func make(_ path: String) throws -> URL {
        let url = base.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func move(_ from: String, to: String) throws {
        try FileManager.default.moveItem(at: base.appendingPathComponent(from), to: base.appendingPathComponent(to))
    }

    func delete(_ path: String) throws {
        try FileManager.default.removeItem(at: base.appendingPathComponent(path))
    }

    func path(_ relative: String) -> String {
        base.appendingPathComponent(relative).path
    }
}

@Suite("Folder links (S5 rules)")
struct FolderLinkTests {
    @Test func aLinkedFolderIsHealthyAndSurvivesBeingStored() throws {
        let folders = try Folders()
        let url = try folders.make("nlp-report")

        let bookmark = try folders.access.bookmark(url, root: nil)
        let stored = try JSONDecoder().decode(FolderBookmark.self, from: JSONEncoder().encode(bookmark))

        #expect(bookmark.path == url.path)
        #expect(SystemFolderAccess().check(stored) == .healthy(path: url.path))
    }

    @Test func aRenamedFolderIsFollowedAndItsLinkRefreshed() throws {
        let folders = try Folders()
        let bookmark = try folders.access.bookmark(try folders.make("figures"), root: nil)

        try folders.move("figures", to: "figures-v2")

        guard case .moved(let path, let refreshed) = folders.access.check(bookmark) else {
            Issue.record("not followed: \(folders.access.check(bookmark))")
            return
        }
        #expect(path == folders.path("figures-v2"))
        #expect(refreshed.path == path)
        #expect(folders.access.check(refreshed) == .healthy(path: path))
    }

    @Test func aDeletedFolderNeedsRepair() throws {
        let folders = try Folders()
        let bookmark = try folders.access.bookmark(try folders.make("figures"), root: nil)

        try folders.delete("figures")

        #expect(folders.access.check(bookmark) == .needsRepair(.missing))
    }

    // S5 T5: the bookmark resolves to the new folder; only the inode tells.
    @Test func aFolderRecreatedAtTheSamePathNeedsRepair() throws {
        let folders = try Folders()
        let bookmark = try folders.access.bookmark(try folders.make("figures"), root: nil)

        try folders.delete("figures")
        try folders.make("figures")

        #expect(folders.access.check(bookmark) == .needsRepair(.replaced(path: folders.path("figures"))))
    }

    @Test func aFolderInTheTrashNeedsRepair() throws {
        let folders = try Folders()
        let bookmark = try folders.access.bookmark(try folders.make("figures"), root: nil)
        try folders.make(".Trash")

        try folders.move("figures", to: ".Trash/figures")

        #expect(folders.access.check(bookmark) == .needsRepair(.inTrash))
    }

    @Test func aFolderMovedOutOfItsRootNeedsRepair() throws {
        let folders = try Folders()
        let root = try folders.make("Projects")
        let bookmark = try folders.access.bookmark(try folders.make("Projects/nlp-report"), root: root.path)
        try folders.make("Elsewhere")

        try folders.move("Projects/nlp-report", to: "Elsewhere/nlp-report")

        #expect(folders.access.check(bookmark)
            == .needsRepair(.outsideRoot(path: folders.path("Elsewhere/nlp-report"), root: root.path)))
    }

    @Test func aFolderMovedWithinItsRootIsFollowed() throws {
        let folders = try Folders()
        let root = try folders.make("Projects")
        let bookmark = try folders.access.bookmark(try folders.make("Projects/nlp-report"), root: root.path)
        try folders.make("Projects/Archive")

        try folders.move("Projects/nlp-report", to: "Projects/Archive/nlp-report")

        guard case .moved(let path, let refreshed) = folders.access.check(bookmark) else {
            Issue.record("not followed")
            return
        }
        #expect(path == folders.path("Projects/Archive/nlp-report"))
        #expect(refreshed.root == root.path)
    }

    @Test func aFolderOutsideItsRootCannotBeLinked() throws {
        let folders = try Folders()
        let root = try folders.make("Projects")

        #expect(throws: FolderLinkError.outsideRoot) {
            try folders.access.bookmark(try folders.make("Elsewhere"), root: root.path)
        }
    }

    @Test func aFileIsNotAFolder() throws {
        let folders = try Folders()
        let file = folders.base.appendingPathComponent("notes.txt")
        try Data().write(to: file)

        #expect(throws: FolderLinkError.notAFolder) { try folders.access.bookmark(file, root: nil) }
    }

    @Test func aDiskThatIsNotConnectedIsNamed() {
        #expect(SystemFolderAccess.missingVolume(for: "/Volumes/FocusPilotNoSuchDisk/thesis") == "FocusPilotNoSuchDisk")
        #expect(SystemFolderAccess.missingVolume(for: "/Users/owner/Projects/thesis") == nil)
        #expect(SystemFolderAccess.missingVolume(for: "/Volumes") == nil)
    }
}

@Suite("Root containment (S5 rule 5)")
struct FolderContainmentTests {
    @Test func insideOutsideAndLookalikePrefixes() throws {
        let folders = try Folders()
        let root = try folders.make("Root")
        try folders.make("Root/inside")
        try folders.make("RootB/other")

        #expect(FolderContainment.contains(root: root.path, path: folders.path("Root/inside")))
        #expect(FolderContainment.contains(root: root.path, path: root.path))
        #expect(!FolderContainment.contains(root: root.path, path: folders.path("RootB/other")))
        #expect(!FolderContainment.contains(root: root.path, path: folders.path("Root/../RootB/other")))
    }

    @Test func aSymlinkOutOfTheRootIsOutside() throws {
        let folders = try Folders()
        let root = try folders.make("Root")
        let outside = try folders.make("outside")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)

        #expect(!FolderContainment.contains(root: root.path, path: folders.path("Root/escape")))
    }

    @Test func caseAndUnicodeFormDoNotMatterOnThisVolume() throws {
        let folders = try Folders()
        let root = try folders.make("Caf\u{E9}")
        try folders.make("Caf\u{E9}/notes")

        // The temporary volume is case-insensitive, like the owner's.
        #expect(FolderContainment.contains(root: root.path, path: folders.path("CAFE\u{301}/notes")))
    }
}
