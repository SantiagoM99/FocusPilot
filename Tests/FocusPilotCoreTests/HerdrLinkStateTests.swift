import Foundation
import Testing
@testable import FocusPilotCore

@Suite("Herdr link state")
struct HerdrLinkStateTests {
    private let nlpLink = HerdrLink(server: herdrServer, workspaceID: "w4", label: "NLP report", cwd: nlpWorkspace.cwd)

    @Test func linkIsLiveWhileItsWorkspaceIsListed() {
        let connection = HerdrConnection.connected(herdrServer, [nlpWorkspace])
        #expect(HerdrLinkState(nlpLink, connection) == .live(nlpWorkspace))
    }

    @Test func workspaceGoneFromTheListIsNotFound() {
        #expect(HerdrLinkState(nlpLink, .connected(herdrServer, [thesisWorkspace])) == .notFound)
    }

    @Test func sameIDOnARestartedServerIsNotFound() {
        // After a restart "w4" may be a different workspace.
        let reused = HerdrWorkspace(id: "w4", label: "Something else", cwd: nil, isLinkedWorktree: false)
        #expect(HerdrLinkState(nlpLink, .connected(restartedHerdrServer, [reused])) == .notFound)
    }

    @Test func withoutHerdrTheStateIsUnknownNotMissing() {
        #expect(HerdrLinkState(nlpLink, .disconnected(.notRunning)) == .unknown)
    }

    @Test func relinkSuggestsTheWorkspaceWithTheSameLabelAndCheckout() {
        let renumbered = HerdrWorkspace(id: "w1", label: "NLP report", cwd: nlpWorkspace.cwd, isLinkedWorktree: false)
        let sameLabelElsewhere = HerdrWorkspace(id: "w2", label: "NLP report", cwd: "/tmp/other", isLinkedWorktree: false)

        #expect(HerdrRelink.suggestion(for: nlpLink, among: [thesisWorkspace, sameLabelElsewhere, renumbered]) == renumbered)
        #expect(HerdrRelink.suggestion(for: nlpLink, among: [thesisWorkspace, sameLabelElsewhere]) == nil)
    }

    @Test func pickerMarksWorkspacesThatAlreadyHaveAProject() {
        let projects = [
            ProjectSummary(id: 1, title: "NLP", openTaskCount: 2, nearestDeadline: nil, herdrLink: nlpLink),
            ProjectSummary(id: 2, title: "Admin", openTaskCount: 1, nearestDeadline: nil),
        ]
        let rows = HerdrImportRow.rows(for: [nlpWorkspace, thesisWorkspace, agentWorktree], on: herdrServer, projects: projects)

        #expect(rows.map(\.workspace) == [nlpWorkspace, thesisWorkspace, agentWorktree])
        #expect(rows.map(\.linkedProjectTitle) == ["NLP", nil, nil])
        #expect(rows.map(\.canImport) == [false, true, true])
    }

    @Test func aLinkFromBeforeARestartDoesNotMarkTheRenumberedWorkspace() {
        let projects = [ProjectSummary(id: 1, title: "NLP", openTaskCount: 0, nearestDeadline: nil, herdrLink: nlpLink)]
        let rows = HerdrImportRow.rows(for: [nlpWorkspace], on: restartedHerdrServer, projects: projects)
        #expect(rows.map(\.canImport) == [true])
    }
}
