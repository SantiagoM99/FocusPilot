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
        (FolderProblem.missing, "Not found · deleted, or moved where FocusPilot can’t follow"),
        (.volumeUnavailable("Thesis"), "On the disk “Thesis”, which isn’t connected"),
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

    @Test func aPageOnABlockedSiteSaysItStaysBlocked() {
        let rules = [BlockRuleSet(targets: [.site(domain: "youtube.com")], activation: .sessionOnly)]

        #expect(ResourceText.sessionNote(for: try! WebPageLink("youtube.com/watch?v=1"), rules: rules)
            == "Blocked by your rules, also in this project’s sessions")
        #expect(ResourceText.sessionNote(for: try! WebPageLink("m.youtube.com/watch?v=1"), rules: rules)
            == "Blocked by your rules, also in this project’s sessions")
        #expect(ResourceText.sessionNote(for: try! WebPageLink("arxiv.org/abs/1"), rules: rules)
            == "Allowed in this project’s sessions")
    }

    @Test func linkingABlockedPageSaysHowToReachIt() {
        let rules = [BlockRuleSet(targets: [.site(domain: "youtube.com")], activation: .sessionOnly)]

        #expect(ResourceText.blockedPageHelp(for: try! WebPageLink("youtube.com/watch?v=1"), rules: rules)
            == "Linking it doesn’t unblock it. When you need it during a session, ask for a timed exception on the blocked page.")
        #expect(ResourceText.blockedPageHelp(for: try! WebPageLink("arxiv.org"), rules: rules) == nil)
    }

    @Test(arguments: [
        (3, 0, [String](), "Opened 3 items."),
        (1, 0, [String](), "Opened 1 item."),
        (2, 1, ["figures"], "Opened 2 of 3. “figures” needs repair."),
        (0, 2, ["figures", "data"], "Opened 0 of 2. “figures” and “data” need repair."),
        (0, 0, [String](), "Nothing to open. Choose what opens with this task in Resources."),
    ])
    func theLaunchResultSaysWhatOpened(opened: Int, broken: Int, names: [String], text: String) {
        #expect(ResourceText.launchResult(opened: opened, needingRepair: names) == text)
    }

    @Test func aFolderThatMovedBeforeLaunchIsMentioned() {
        #expect(ResourceText.launchResult(opened: 2, needingRepair: [], moved: [MovedFolder(name: "figures", path: "/Users/owner/x")],
                                          home: home)
            == "Opened 2 items. “figures” had moved; it opened from ~/x.")
    }
}
