import Foundation
import Testing
@testable import FocusPilotCore

/// A coordinator on a temporary database, with real folders in a temporary
/// directory and a fake Herdr.
private struct ContextFixture {
    let location: StorageLocation
    let folders: URL
    let clock = SettableClock(wednesdayMorningInBogota)
    let publisher = RecordingPolicyPublisher()
    let herdr = FakeHerdrAgents(.connected(herdrServer, [agent(.working)]))
    let coordinator: FocusCoordinator
    /// "Explain baseline results" in project "NLP report", pinned as Now.
    let task: Int64
    let project: Int64

    init() async throws {
        location = StorageLocation(directory: try makeTemporaryDirectory())
        folders = URL(fileURLWithPath: FolderContainment.canonical(try makeTemporaryDirectory().path)!)
        coordinator = try Self.coordinator(location, clock, publisher, herdr)
        try await coordinator.capture(NewTask(title: "Explain baseline results", projectName: "NLP report"))
        let item = try await coordinator.todayTasks()[0]
        task = item.id
        project = try #require(item.projectID)
        try await coordinator.moveTask(task, to: .now, .top)
    }

    func relaunched() throws -> FocusCoordinator {
        try Self.coordinator(location, clock, publisher, herdr)
    }

    private static func coordinator(_ location: StorageLocation, _ clock: SettableClock, _ publisher: RecordingPolicyPublisher,
                                    _ herdr: FakeHerdrAgents) throws -> FocusCoordinator {
        let now: @Sendable () -> Date = { clock.now }
        return FocusCoordinator(repository: try TaskRepository(location: location, now: now), agents: herdr,
                                publisher: publisher, now: now)
    }

    @discardableResult
    func folder(_ name: String) throws -> URL {
        let url = folders.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func otherTask(project: String? = nil) async throws -> Int64 {
        try await coordinator.capture(NewTask(title: "Reply to co-advisor", projectName: project))
        return try await coordinator.todayTasks().first { $0.title == "Reply to co-advisor" }!.id
    }
}

@Suite("Context links")
struct ContextLinkTests {
    @Test func linkedFoldersAndPagesSurviveARelaunch() async throws {
        let fixture = try await ContextFixture()
        let repo = try fixture.folder("nlp-report")

        try await fixture.coordinator.linkFolder(repo, to: .task(fixture.task))
        try await fixture.coordinator.linkWebPage("overleaf.com/project/nlp-report", to: .project(fixture.project))

        let context = try await fixture.relaunched().context(forTask: fixture.task)
        #expect(context.resources.map(\.resource.name) == ["nlp-report", "overleaf.com/project/nlp-report"])
        #expect(context.resources.map(\.isFromProject) == [false, true])
        #expect(context.resources[0].folder == .healthy(path: repo.path))
        #expect(context.resources[1].folder == nil)
    }

    @Test func anInvalidPageIsRefusedAndNothingIsSaved() async throws {
        let fixture = try await ContextFixture()

        await #expect(throws: WebPageLinkError.invalid) {
            try await fixture.coordinator.linkWebPage("overleaf", to: .task(fixture.task))
        }
        #expect(try await fixture.coordinator.context(forTask: fixture.task).resources.isEmpty)
    }

    @Test func anotherTasksResourcesAreNotShown() async throws {
        let fixture = try await ContextFixture()
        let other = try await fixture.otherTask()
        try await fixture.coordinator.linkWebPage("arxiv.org", to: .task(other))

        #expect(try await fixture.coordinator.context(forTask: fixture.task).resources.isEmpty)
        #expect(try await fixture.coordinator.context(forTask: other).resources.count == 1)
    }

    @Test func aMovedFolderIsFollowedAndTheNewPathKept() async throws {
        let fixture = try await ContextFixture()
        try await fixture.coordinator.linkFolder(try fixture.folder("figures"), to: .task(fixture.task))
        try FileManager.default.moveItem(at: fixture.folders.appendingPathComponent("figures"),
                                         to: fixture.folders.appendingPathComponent("figures-v2"))
        let newPath = fixture.folders.appendingPathComponent("figures-v2").path

        let first = try await fixture.coordinator.context(forTask: fixture.task).resources[0]
        #expect(first.folder == .moved(path: newPath, refreshed: first.resource.folderBookmark!))
        #expect(first.resource.folderBookmark?.path == newPath)

        let again = try await fixture.relaunched().context(forTask: fixture.task).resources[0]
        #expect(again.folder == .healthy(path: newPath))
    }

    @Test func aBrokenFolderShowsNeedsRepairAndRelinkFixesIt() async throws {
        let fixture = try await ContextFixture()
        let link = try await fixture.coordinator.linkFolder(try fixture.folder("figures"), to: .task(fixture.task))
        try FileManager.default.removeItem(at: fixture.folders.appendingPathComponent("figures"))
        #expect(try await fixture.coordinator.context(forTask: fixture.task).resources[0].folder == .needsRepair(.missing))

        let chosen = try fixture.folder("figures-final")
        try await fixture.coordinator.relinkFolder(link.id, to: chosen)

        let resource = try await fixture.coordinator.context(forTask: fixture.task).resources[0]
        #expect(resource.folder == .healthy(path: chosen.path))
        #expect(resource.resource.id == link.id)
    }

    @Test func aFolderRecreatedAtThePathCanBeAcceptedByTheOwner() async throws {
        let fixture = try await ContextFixture()
        let link = try await fixture.coordinator.linkFolder(try fixture.folder("figures"), to: .task(fixture.task))
        try FileManager.default.removeItem(at: fixture.folders.appendingPathComponent("figures"))
        let recreated = try fixture.folder("figures")
        #expect(try await fixture.coordinator.context(forTask: fixture.task).resources[0].folder
            == .needsRepair(.replaced(path: recreated.path)))

        try await fixture.coordinator.useFolderNowAtPath(link.id)

        #expect(try await fixture.coordinator.context(forTask: fixture.task).resources[0].folder == .healthy(path: recreated.path))
    }

    @Test func unlinkingRemovesOnlyTheLink() async throws {
        let fixture = try await ContextFixture()
        let url = try fixture.folder("figures")
        let link = try await fixture.coordinator.linkFolder(url, to: .task(fixture.task))

        try await fixture.coordinator.unlinkResource(link.id)

        #expect(try await fixture.coordinator.context(forTask: fixture.task).resources.isEmpty)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}

@Suite("The launch set")
struct LaunchSetTests {
    @Test func onlyTheLaunchSetOpensInItsOrder() async throws {
        let fixture = try await ContextFixture()
        let coordinator = fixture.coordinator
        let repo = try await coordinator.linkFolder(try fixture.folder("nlp-report"), to: .task(fixture.task))
        _ = try await coordinator.linkFolder(try fixture.folder("figures"), to: .task(fixture.task))
        let overleaf = try await coordinator.linkWebPage("overleaf.com/project/nlp-report", to: .project(fixture.project))
        let agentLink = try await coordinator.linkAgent(agent(.working), on: herdrServer, workspaceLabel: "NLP report",
                                                        toTask: fixture.task)

        try await coordinator.setLaunch(.resource(overleaf.id), included: true)
        try await coordinator.setLaunch(.agent(agentLink.id), included: true)
        try await coordinator.setLaunch(.resource(repo.id), included: true)

        let plan = try await coordinator.prepareLaunch(forTask: fixture.task)
        #expect(plan.steps.map(\.item) == [.resource(overleaf.id), .agent(agentLink.id), .resource(repo.id)])
        #expect(plan.needsRepair.isEmpty)
        #expect(plan.steps[0] == .webPage(overleaf.id, URL(string: "https://overleaf.com/project/nlp-report")!))
    }

    @Test func movingAnItemEarlierChangesTheOrder() async throws {
        let fixture = try await ContextFixture()
        let a = try await fixture.coordinator.linkWebPage("arxiv.org", to: .task(fixture.task))
        let b = try await fixture.coordinator.linkWebPage("overleaf.com", to: .task(fixture.task))
        try await fixture.coordinator.setLaunch(.resource(a.id), included: true)
        try await fixture.coordinator.setLaunch(.resource(b.id), included: true)

        try await fixture.coordinator.moveEarlier(.resource(b.id), forTask: fixture.task)

        #expect(try await fixture.coordinator.context(forTask: fixture.task).launchSet == [.resource(b.id), .resource(a.id)])
        #expect(try await fixture.coordinator.prepareLaunch(forTask: fixture.task).steps.map(\.item) == [.resource(b.id), .resource(a.id)])
    }

    @Test func takingAnItemOutOfTheLaunchSetKeepsItLinked() async throws {
        let fixture = try await ContextFixture()
        let page = try await fixture.coordinator.linkWebPage("arxiv.org", to: .task(fixture.task))
        try await fixture.coordinator.setLaunch(.resource(page.id), included: true)

        try await fixture.coordinator.setLaunch(.resource(page.id), included: false)

        let context = try await fixture.coordinator.context(forTask: fixture.task)
        #expect(context.launchSet.isEmpty)
        #expect(context.resources.count == 1)
        #expect(try await fixture.coordinator.prepareLaunch(forTask: fixture.task).steps.isEmpty)
    }

    @Test func aBrokenFolderIsRevalidatedBeforeLaunchAndReportedNotOpened() async throws {
        let fixture = try await ContextFixture()
        let figures = try await fixture.coordinator.linkFolder(try fixture.folder("figures"), to: .task(fixture.task))
        let page = try await fixture.coordinator.linkWebPage("arxiv.org", to: .task(fixture.task))
        try await fixture.coordinator.setLaunch(.resource(figures.id), included: true)
        try await fixture.coordinator.setLaunch(.resource(page.id), included: true)
        try FileManager.default.removeItem(at: fixture.folders.appendingPathComponent("figures"))

        let plan = try await fixture.coordinator.prepareLaunch(forTask: fixture.task)

        #expect(plan.steps.map(\.item) == [.resource(page.id)])
        #expect(plan.needsRepair.map(\.resource.id) == [figures.id])
        #expect(plan.needsRepair.first?.problem == .missing)
    }

    @Test func aMovedFolderStillOpensAndIsReported() async throws {
        let fixture = try await ContextFixture()
        let figures = try await fixture.coordinator.linkFolder(try fixture.folder("figures"), to: .task(fixture.task))
        try await fixture.coordinator.setLaunch(.resource(figures.id), included: true)
        try FileManager.default.moveItem(at: fixture.folders.appendingPathComponent("figures"),
                                         to: fixture.folders.appendingPathComponent("figures-v2"))

        let plan = try await fixture.coordinator.prepareLaunch(forTask: fixture.task)

        #expect(plan.steps.map(\.item) == [.resource(figures.id)])
        #expect(plan.moved == [MovedFolder(name: "figures", path: fixture.folders.appendingPathComponent("figures-v2").path)])
    }

    @Test func openingExistingWorkCreatesNoFoldersTasksOrWorkspaces() async throws {
        let fixture = try await ContextFixture()
        let repo = try await fixture.coordinator.linkFolder(try fixture.folder("nlp-report"), to: .task(fixture.task))
        try await fixture.coordinator.setLaunch(.resource(repo.id), included: true)
        let before = try FileManager.default.contentsOfDirectory(atPath: fixture.folders.path)
        let tasks = try await fixture.coordinator.todayTasks()

        _ = try await fixture.coordinator.prepareLaunch(forTask: fixture.task)

        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.folders.path) == before)
        #expect(try await fixture.coordinator.todayTasks() == tasks)
        #expect(!fixture.herdr.calls.contains { if case .focus = $0 { true } else { false } })
    }

    @Test func aProjectResourceInTheLaunchSetOpensForEachOfItsTasks() async throws {
        let fixture = try await ContextFixture()
        let other = try await fixture.otherTask(project: "NLP report")
        let page = try await fixture.coordinator.linkWebPage("overleaf.com", to: .project(fixture.project))
        try await fixture.coordinator.setLaunch(.resource(page.id), included: true)

        #expect(try await fixture.coordinator.prepareLaunch(forTask: other).steps.map(\.item) == [.resource(page.id)])
    }
}

@Suite("Context resources in the session's allowed list (decision 0004)")
struct ContextAllowanceTests {
    private func allowedDomains(_ fixture: ContextFixture) async -> [String] {
        await fixture.publisher.published.last?.allowed.domains ?? []
    }

    @Test func theProjectsPagesAreAllowedOnlyWhileItsSessionRuns() async throws {
        let fixture = try await ContextFixture()
        try await fixture.coordinator.linkWebPage("docs.google.com/document/d/1", to: .project(fixture.project))
        try await fixture.coordinator.linkWebPage("arxiv.org/abs/1", to: .task(fixture.task))
        #expect(await !allowedDomains(fixture).contains("arxiv.org"))

        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)

        #expect(await allowedDomains(fixture).contains("arxiv.org"))
        #expect(await allowedDomains(fixture).contains("docs.google.com"))

        _ = try await fixture.coordinator.complete()
        #expect(await !allowedDomains(fixture).contains("arxiv.org"))
    }

    @Test func otherProjectsPagesAreNotAllowed() async throws {
        let fixture = try await ContextFixture()
        let other = try await fixture.otherTask(project: "Applications")
        try await fixture.coordinator.linkWebPage("arxiv.org", to: .task(other))

        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)

        #expect(await !allowedDomains(fixture).contains("arxiv.org"))
    }

    @Test func aPageLinkedDuringTheSessionIsAllowedRightAway() async throws {
        let fixture = try await ContextFixture()
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .strict)

        try await fixture.coordinator.linkWebPage("arxiv.org", to: .task(fixture.task))

        #expect(await allowedDomains(fixture).contains("arxiv.org"))
    }

    // Linking never weakens blocking: Chrome does not unblock allowed
    // domains, and the lists must not contradict each other.
    @Test func aPageOnABlockedSiteStaysBlocked() async throws {
        let fixture = try await ContextFixture()
        try await fixture.coordinator.saveRuleSet(BlockRuleSet(targets: [.site(domain: "youtube.com")], activation: .sessionOnly))
        try await fixture.coordinator.linkWebPage("youtube.com/watch?v=lecture", to: .task(fixture.task))

        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)

        let policy = try #require(await fixture.publisher.published.last)
        #expect(!policy.allowed.domains.contains("youtube.com"))
        #expect(policy.session?.targets.domains == ["youtube.com"])
    }

    @Test func aPageAlreadyAllowedIsNotListedTwice() async throws {
        let fixture = try await ContextFixture()
        try await fixture.coordinator.linkWebPage("www.overleaf.com/project/1", to: .task(fixture.task))

        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)

        #expect(await allowedDomains(fixture).filter { $0 == "overleaf.com" }.count == 1)
    }
}
