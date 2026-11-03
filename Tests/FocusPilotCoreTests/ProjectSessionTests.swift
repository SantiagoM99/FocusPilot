import Foundation
import GRDB
import Testing
@testable import FocusPilotCore

/// #56 (decision 0004): a session covers projects, not one task. Now can
/// change inside it, and every task that becomes Now is recorded.
@Suite("Sessions that cover projects")
struct ProjectSessionTests {
    private func emptyFixture() throws -> (FocusCoordinator, RecordingPolicyPublisher) {
        let publisher = RecordingPolicyPublisher()
        let repository = try TaskRepository(location: StorageLocation(directory: makeTemporaryDirectory()),
                                            now: { wednesdayMorningInBogota })
        return (FocusCoordinator(repository: repository, publisher: publisher, now: { wednesdayMorningInBogota }), publisher)
    }

    private func pin(_ title: String, project: String? = nil, _ fixture: SessionFixture) async throws -> Int64 {
        try await fixture.coordinator.capture(NewTask(title: title, projectName: project))
        let id = try #require(try await fixture.coordinator.todayTasks().first { $0.title == title }?.id)
        try await fixture.coordinator.moveTask(id, to: .now, .top)
        return id
    }

    private func projectID(_ title: String, _ coordinator: FocusCoordinator) async throws -> Int64 {
        try #require(try await coordinator.projects().first { $0.title == title }?.id)
    }

    private func touched(_ fixture: SessionFixture) async throws -> [Int64?] {
        try await fixture.coordinator.pilotEvents(since: .distantPast).filter { $0.kind == .taskTouched }.map(\.taskID)
    }

    @Test func aSessionCoversAllProjectsByDefaultAndNeedsNothingInNow() async throws {
        let (coordinator, publisher) = try emptyFixture()

        try await coordinator.startSession(duration: 25 * 60, mode: .normal)

        let session = try #require(await coordinator.snapshot().activeSession)
        #expect(session.scope == .allProjects)
        #expect(session.taskID == nil && session.action == nil)
        #expect(await publisher.deliveries.last?.focus == FocusContext(title: "Nothing in Now", covers: "Covers all projects"))
    }

    @Test func aSessionCanBeNarrowedToChosenProjects() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.capture(NewTask(title: "Run ablation", projectName: "NLP report"))
        try await fixture.coordinator.capture(NewTask(title: "Fix parser", projectName: "FocusPilot"))
        try await fixture.coordinator.capture(NewTask(title: "Book flights", projectName: "Travel"))
        let nlp = try await projectID("NLP report", fixture.coordinator)
        let app = try await projectID("FocusPilot", fixture.coordinator)

        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal, projects: [app, nlp])

        let session = try #require(await fixture.coordinator.snapshot().activeSession)
        // In the order the projects are listed: alphabetical.
        #expect(session.scope == SessionScope(projects: [ScopedProject(id: app, title: "FocusPilot"),
                                                         ScopedProject(id: nlp, title: "NLP report")]))
        #expect(SessionText.scope(session.scope) == "FocusPilot and NLP report")
    }

    @Test func aProjectThatNoLongerExistsCannotBeChosen() async throws {
        let fixture = try await SessionFixture()

        await #expect(throws: FocusCoordinator.SessionError.unknownProject) {
            try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal, projects: [999])
        }
        #expect(await fixture.coordinator.snapshot().activeSession == nil)
    }

    @Test func nowCanChangeInsideASessionWithoutEndingIt() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)
        let started = try #require(await fixture.coordinator.snapshot().activeSession)
        fixture.advance(minutes: 5)

        let next = try await pin("Reply to Ana", project: "Thesis", fixture)

        let session = try #require(await fixture.coordinator.snapshot().activeSession)
        #expect(session.id == started.id && session.phase == .running && session.plannedEnd == started.plannedEnd)
        #expect(session.taskID == next && session.action == "Reply to Ana")
        // The blocked page names the new Now task.
        let delivery = try #require(await fixture.publisher.deliveries.last)
        #expect(delivery.focus == FocusContext(title: "Reply to Ana", projectTitle: "Thesis"))
        #expect(delivery.policy.session?.end == started.plannedEnd)
    }

    @Test func everyTaskThatBecomesNowInASessionIsRecorded() async throws {
        let fixture = try await SessionFixture()
        let first = try #require(try await fixture.coordinator.todayTasks().first?.id)
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)
        let session = try #require(await fixture.coordinator.snapshot().activeSession)

        let second = try await pin("Reply to Ana", fixture)
        fixture.advance(minutes: 3)
        try await fixture.coordinator.moveTask(first, to: .now, .top)

        #expect(try await touched(fixture) == [first, second, first])
        let events = try await fixture.coordinator.pilotEvents(since: .distantPast).filter { $0.kind == .taskTouched }
        #expect(events.allSatisfy { $0.sessionID == session.id })
        #expect(events.last?.at == fixture.clock.now)
    }

    @Test func outsideASessionChangingNowRecordsNothing() async throws {
        let fixture = try await SessionFixture()

        _ = try await pin("Reply to Ana", fixture)

        #expect(try await touched(fixture).isEmpty)
        #expect(await fixture.publisher.deliveries.isEmpty)
    }

    @Test func emptyingNowKeepsTheSessionWithNoTask() async throws {
        let fixture = try await SessionFixture()
        let only = try #require(try await fixture.coordinator.todayTasks().first?.id)
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)

        try await fixture.coordinator.moveTask(only, to: .later, .top)

        let session = try #require(await fixture.coordinator.snapshot().activeSession)
        #expect(session.taskID == nil && session.action == nil)
        #expect(try await touched(fixture).count == 1)
        #expect(await fixture.publisher.deliveries.last?.focus == FocusContext(title: "Nothing in Now", covers: "Covers all projects"))
    }

    // Decision 0003 still holds: switching Now is not ending early or an exception.
    @Test func inAStrictSessionSwitchingNeedsNoWaitAndEndingEarlyStillDoes() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .strict)

        _ = try await pin("Reply to Ana", fixture)

        #expect(await fixture.publisher.deliveries.last?.policy.session?.mode == .strict)
        #expect(try await fixture.coordinator.complete() == .needsConfirmation)
        #expect(try await fixture.coordinator.complete(confirmed: true)
            == .waitUntil(fixture.clock.now.addingTimeInterval(StrictEarlyEnd.wait)))
        _ = try await pin("Write intro", fixture)
        fixture.advance(seconds: 60)
        #expect(try await fixture.coordinator.complete() == .completed)
    }

    @Test func relaunchingKeepsTheScopeAndTheTaskInNow() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.capture(NewTask(title: "Run ablation", projectName: "NLP report"))
        let nlp = try await projectID("NLP report", fixture.coordinator)
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal, projects: [nlp])
        let next = try await pin("Reply to Ana", fixture)

        let relaunched = try fixture.relaunched()
        try await relaunched.launch()

        let session = try #require(await relaunched.snapshot().activeSession)
        #expect(session.scope == SessionScope(projects: [ScopedProject(id: nlp, title: "NLP report")]))
        #expect(session.taskID == next && session.action == "Reply to Ana")
    }

    // Review of #60: a Now change and a session step at the same time.
    // Each round races them; neither may undo the other.
    @Test(arguments: 0..<25)
    func aNowChangeRacingTheEndLeavesTheSessionEndedOnce(round: Int) async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.capture(NewTask(title: "Reply to Ana"))
        let next = try #require(try await fixture.coordinator.todayTasks().first { $0.title == "Reply to Ana" }?.id)
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)
        fixture.advance(minutes: 26)

        async let moved: Void = fixture.coordinator.moveTask(next, to: .now, .top)
        async let reconciled: Void = fixture.coordinator.reconcile()
        _ = try await (moved, reconciled)

        #expect(await fixture.coordinator.snapshot().session?.hasEnded == true)
        #expect(await fixture.publisher.deliveries.last?.policy.session == nil)
        #expect(await fixture.notices.delivered.count == 1, "The end is announced once")
        let relaunched = try fixture.relaunched()
        try await relaunched.launch()
        #expect(await relaunched.snapshot().session?.hasEnded == true)
    }

    @Test(arguments: 0..<25)
    func aNowChangeRacingAPauseKeepsBoth(round: Int) async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.capture(NewTask(title: "Reply to Ana"))
        let next = try #require(try await fixture.coordinator.todayTasks().first { $0.title == "Reply to Ana" }?.id)
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)

        async let moved: Void = fixture.coordinator.moveTask(next, to: .now, .top)
        async let paused: Void = fixture.coordinator.pause()
        _ = try await (moved, paused)

        let session = try #require(await fixture.coordinator.snapshot().activeSession)
        #expect(session.phase == .paused(since: fixture.clock.now) && session.taskID == next)
        #expect(await fixture.publisher.deliveries.last?.policy.session == nil, "Paused normal sessions lift the rules")
        let relaunched = try fixture.relaunched()
        try await relaunched.launch()
        let stored = try #require(await relaunched.snapshot().activeSession)
        #expect(stored.phase == session.phase && stored.taskID == next)
    }

    // Review of #60: a renamed Now task is renamed in the session too; it is not a new task.
    @Test func renamingTheTaskInNowRenamesItInTheSession() async throws {
        let fixture = try await SessionFixture()
        let first = try #require(try await fixture.coordinator.todayTasks().first?.id)
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)
        try await DatabaseQueue(path: fixture.location.ownerDatabaseURL.path).write { db in
            try db.execute(sql: "UPDATE task SET title = 'Explain the baseline' WHERE id = ?", arguments: [first])
        }

        try await fixture.coordinator.capture(NewTask(title: "Book flights"))

        #expect(await fixture.coordinator.snapshot().activeSession?.action == "Explain the baseline")
        #expect(await fixture.publisher.deliveries.last?.focus?.title == "Explain the baseline")
        #expect(try await touched(fixture) == [first], "Not a new task")
    }

    // Review of #60: the move is the owner's; the session catches up on the next change.
    @Test func aMoveStandsWhenTheSessionCannotFollowIt() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal)
        try await DatabaseQueue(path: fixture.location.ownerDatabaseURL.path).write { db in
            try db.execute(sql: "CREATE TRIGGER refuse BEFORE UPDATE ON focusSession BEGIN SELECT RAISE(ABORT, 'refused'); END")
        }

        let next = try await pin("Reply to Ana", fixture)

        #expect(try await fixture.coordinator.todayTasks().first { $0.status == .now }?.id == next)
    }

    // Owner default (review of #60): a task from outside the chosen projects
    // may be pinned; its project is allowed too, and blocking does not change.
    @Test func pinningATaskFromOutsideTheChosenProjectsAllowsItsProject() async throws {
        let fixture = try await SessionFixture()
        try await fixture.coordinator.capture(NewTask(title: "Run ablation", projectName: "NLP report"))
        try await fixture.coordinator.capture(NewTask(title: "Draft chapter 3", projectName: "Thesis"))
        let nlp = try await projectID("NLP report", fixture.coordinator)
        let thesis = try await projectID("Thesis", fixture.coordinator)
        try await fixture.coordinator.startSession(duration: 25 * 60, mode: .normal, projects: [nlp])
        let before = try #require(await fixture.publisher.deliveries.last?.policy)

        _ = try await pin("Draft chapter 3", fixture)
        _ = try await pin("Run ablation", fixture)
        _ = try await pin("Draft chapter 3", fixture)

        let scope = try #require(await fixture.coordinator.snapshot().activeSession?.scope)
        #expect(scope.projects == [ScopedProject(id: nlp, title: "NLP report")], "What it covers is unchanged")
        #expect(scope.alsoAllowed == [ScopedProject(id: thesis, title: "Thesis")], "Added once")
        #expect(SessionText.outsideNote(scope, projectID: thesis) == "Outside this session's projects")
        #expect(SessionText.outsideNote(scope, projectID: nlp) == nil)
        let after = try #require(await fixture.publisher.deliveries.last?.policy)
        #expect(after.always == before.always && after.session?.targets == before.session?.targets
            && after.allowed == before.allowed)
    }
}
