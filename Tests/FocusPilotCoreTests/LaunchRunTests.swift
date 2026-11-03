import Foundation
import Testing
@testable import FocusPilotCore

/// Open context runs the plan through an opener; every step either opens or
/// is named in the notice, so nothing is skipped silently (#62 review).
@Suite("Running a launch")
struct LaunchRunTests {
    private let page = LaunchStep.webPage(1, URL(string: "https://arxiv.org/abs/1")!)
    private let agent = LaunchStep.agent(2)
    private let workspace = LaunchStep.workspace(3)
    private let names: [ContextItem: String] = [.resource(1): "arxiv.org/abs/1", .agent(2): "agent 2", .workspace(3): "NLP report"]

    private func plan(_ steps: [LaunchStep], broken: [String] = []) -> LaunchPlan {
        let resources = broken.enumerated().map { i, name in
            BrokenResource(resource: ContextResource(id: Int64(100 + i), owner: .task(1),
                                                     target: .folder(FolderBookmark(data: Data(), path: "/x/" + name, inode: 1,
                                                                                    volumeUUID: nil, root: nil)),
                                                     launchOrder: 1, createdAt: .now),
                           problem: .missing)
        }
        return LaunchPlan(steps: steps, needsRepair: resources, moved: [])
    }

    @Test func everyStepOpensInOrder() async {
        var opened: [ContextItem] = []

        let notice = await LaunchRun.run(plan([page, agent, workspace]), names: { names[$0.item] ?? "" }) {
            opened.append($0.item)
            return true
        }

        #expect(opened == [.resource(1), .agent(2), .workspace(3)])
        #expect(notice == "Opened 3 items.")
    }

    @Test func aPageThatDoesNotOpenIsReported() async {
        let notice = await LaunchRun.run(plan([page, agent]), names: { names[$0.item] ?? "" }) { $0 != page }

        #expect(notice == "Opened 1 of 2. “arxiv.org/abs/1” didn’t open.")
    }

    @Test func repairsAndFailuresAreBothNamed() async {
        let notice = await LaunchRun.run(plan([page, agent, workspace], broken: ["figures"]), names: { names[$0.item] ?? "" }) {
            $0 == page
        }

        #expect(notice == "Opened 1 of 4. “figures” needs repair. “agent 2” and “NLP report” didn’t open.")
    }
}
