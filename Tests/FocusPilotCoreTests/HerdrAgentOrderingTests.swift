import Foundation
import Testing
@testable import FocusPilotCore

/// A fake Herdr whose first `agent list` reply is held until the test lets
/// it go, the way a slow `herdr` process keeps the coordinator suspended.
/// Focusing a done agent turns it idle, as Herdr does.
final class HeldHerdrAgents: HerdrAgentSource, @unchecked Sendable {
    private let lock = NSLock()
    private var current: HerdrAgents
    private var held: CheckedContinuation<Void, Never>?
    private var holding = true
    private var released = false
    private(set) var focused = false

    init(_ current: HerdrAgents) { self.current = current }

    func set(_ agents: HerdrAgents) { lock.withLock { current = agents } }
    var isHolding: Bool { lock.withLock { held != nil } }
    var hasFocused: Bool { lock.withLock { focused } }

    func release() {
        lock.withLock {
            released = true
            held?.resume()
            held = nil
        }
    }

    func agents() async -> HerdrAgents {
        let reading = lock.withLock { () -> HerdrAgents? in
            guard holding else { return nil }
            holding = false
            return current
        }
        guard let reading else { return lock.withLock { current } }
        await withCheckedContinuation { continuation in
            lock.withLock {
                if released { continuation.resume() } else { held = continuation }
            }
        }
        return reading
    }

    func output(of paneID: String, on server: HerdrServer) async -> String? { nil }

    func focus(_ paneID: String, on server: HerdrServer) async -> Bool {
        lock.withLock {
            focused = true
            if case .connected(let server, let agents) = current {
                current = .connected(server, agents.map { var seen = $0; if seen.status == .done { seen.status = .idle }; return seen })
            }
        }
        return true
    }
}

@Suite("Herdr agents: one reading at a time")
struct HerdrAgentOrderingTests {
    private let repository: TaskRepository
    private let herdr = HeldHerdrAgents(.connected(herdrServer, [agent(.working)]))
    private let coordinator: FocusCoordinator

    init() throws {
        repository = try TaskRepository(location: StorageLocation(directory: makeTemporaryDirectory()))
        coordinator = FocusCoordinator(repository: repository, agents: herdr)
    }

    /// Gives other tasks up to `limit` to make `condition` true.
    private func wait(upTo limit: Duration = .milliseconds(300), until condition: () -> Bool) async {
        let deadline = ContinuousClock.now + limit
        while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func aSlowPollCannotOverwriteWhatOpenAgentRecordedLater() async throws {
        let taskID = try await repository.addTask(NewTask(title: "Explain baseline results")).id!
        let link = try await coordinator.linkAgent(agent(.working), on: herdrServer, workspaceLabel: nil, toTask: taskID)

        // The poll has read "working" and is still waiting on Herdr when the
        // agent finishes and the owner clicks Open agent.
        let poll = Task { await coordinator.refreshHerdrAgents() }
        await wait { herdr.isHolding }
        herdr.set(.connected(herdrServer, [agent(.done)]))
        let open = Task { await coordinator.openAgent(link.id) }
        await wait { herdr.hasFocused }
        herdr.release()
        _ = await poll.value
        #expect(await open.value == .opened)

        _ = await coordinator.refreshHerdrAgents()

        #expect(try await coordinator.reviewQueue().map(\.kind) == [.finished])
        #expect(try await coordinator.agentLinks().first?.lastStatus == .idle)
    }

    @Test func linkingWaitsForAPollInFlight() async throws {
        // The poll read Herdr before the link existed; its old reading must
        // not become the new link's status.
        let first = try await repository.addTask(NewTask(title: "Explain baseline results")).id!
        _ = try await coordinator.linkAgent(agent(.working, pane: "w4:p9", name: "other"), on: herdrServer,
                                            workspaceLabel: nil, toTask: first)
        let poll = Task { await coordinator.refreshHerdrAgents() }
        await wait { herdr.isHolding }
        herdr.set(.connected(herdrServer, [agent(.done)]))
        let link = Task { try await coordinator.linkAgent(agent(.done), on: herdrServer, workspaceLabel: nil, toTask: first) }
        await wait(upTo: .milliseconds(100)) { false }
        herdr.release()
        _ = await poll.value
        _ = try await link.value

        _ = await coordinator.refreshHerdrAgents()

        #expect(try await coordinator.reviewQueue().isEmpty)
    }
}
