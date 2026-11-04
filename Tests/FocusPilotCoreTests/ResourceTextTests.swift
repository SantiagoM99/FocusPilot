import Foundation
import Testing
@testable import FocusPilotCore

@Suite("Resource text")
struct ResourceTextTests {
    private let home = "/Users/owner"

    @Test func pathsUnderHomeAreShortened() {
        #expect(ResourceText.path("/Users/owner/Projects/nlp-report", home: home) == "~/Projects/nlp-report")
        #expect(ResourceText.path("/Users/ownerB/x", home: home) == "/Users/ownerB/x")
        #expect(ResourceText.path("/Volumes/Thesis/data", home: home) == "/Volumes/Thesis/data")
    }

    @Test(arguments: [
        (FolderProblem.missing, "Not found"),
        (.volumeUnavailable("Thesis"), "Disk “Thesis” not connected"),
        (.replaced(path: "/Users/owner/Projects/figures"), "A different folder is at this path now"),
        (.inTrash, "In the Trash"),
        (.outsideRoot(path: "/Users/owner/Desktop/figures", root: "/Users/owner/Projects"), "Moved out of ~/Projects"),
    ])
    func eachProblemIsSaidPlainly(problem: FolderProblem, text: String) {
        #expect(ResourceText.problem(problem, home: home) == text)
    }

    @Test func aMovedFolderSaysWhereItIsNow() {
        #expect(ResourceText.moved(to: "/Users/owner/Projects/figures-v2", home: home) == "Moved to ~/Projects/figures-v2")
    }

    // Owner decision (0003, 2026-11-03).
    @Test func aPageOnABlockedSiteOpensInNormalSessionsOnly() {
        let rules = [BlockRuleSet(targets: [.site(domain: "youtube.com")], activation: .sessionOnly)]

        #expect(ResourceText.sessionNote(for: try! WebPageLink("youtube.com/watch?v=1"), rules: rules)
            == "Opens in normal sessions")
        #expect(ResourceText.sessionNote(for: try! WebPageLink("m.youtube.com/watch?v=1"), rules: rules)
            == "Opens in normal sessions")
        #expect(ResourceText.sessionNote(for: try! WebPageLink("arxiv.org/abs/1"), rules: rules)
            == "Allowed in this project’s sessions")
    }

    @Test(arguments: [
        (3, 0, [String](), "Opened 3 items."),
        (1, 0, [String](), "Opened 1 item."),
        (2, 1, ["figures"], "Opened 2 of 3. “figures” needs repair."),
        (0, 2, ["figures", "data"], "Opened 0 of 2. “figures” and “data” need repair."),
        (0, 0, [String](), "Nothing to open"),
    ])
    func theLaunchResultSaysWhatOpened(opened: Int, broken: Int, names: [String], text: String) {
        #expect(ResourceText.launchResult(opened: opened, needingRepair: names) == text)
    }

    @Test func itemsThatDidNotOpenAreNamedAfterRepairs() {
        #expect(ResourceText.launchResult(opened: 0, needingRepair: [], failed: ["arxiv.org"]) == "Opened 0 of 1. “arxiv.org” didn’t open.")
    }

    @Test func aFolderThatMovedBeforeLaunchIsMentioned() {
        #expect(ResourceText.launchResult(opened: 2, needingRepair: [], moved: [MovedFolder(name: "figures", path: "/Users/owner/x")],
                                          home: home)
            == "Opened 2 items. “figures” had moved; it opened from ~/x.")
    }
}
