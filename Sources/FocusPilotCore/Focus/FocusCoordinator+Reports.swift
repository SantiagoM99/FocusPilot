import Foundation

/// Agent reports and one-click Accept (#67, decision 0004, Phase 2 start).
/// Receiving a report sends nothing. Accept is the owner's click: it sends
/// the stored message, which must be exactly what the owner was shown, to
/// the stored agent, after checking that agent again. This is the only
/// Herdr write FocusPilot performs.
extension FocusCoordinator {
    /// Stores a report from `focuspilot report`, resolving its target among
    /// Herdr's agents now, so Accept can later check it is the same agent.
    public func receiveReport(_ request: ReportRequest) async throws -> ReportReceipt {
        if let problem = request.problem { throw ReportRefused(reason: problem) }
        let current = await agents?.agents()
        let target = request.to.map { ReportTarget.resolve($0, in: current ?? .disconnected(.notRunning), caller: request.caller) }
        let receipt = try await repository.addReport(request, sourceLabel: Self.sourceLabel(request, current),
                                                     claimedName: request.from, target: target)
        await broadcast()
        return receipt
    }

    /// An inbox report, within the same per-pane limit as the socket's.
    func receiveQueuedReport(_ request: ReportRequest) async throws -> ReportReceipt {
        guard queuedReportLimit.allow(AddRateLimit.key(for: request.caller), at: request.sentAt) else {
            throw ReportRefused(reason: CommandService.reportRateLimitMessage)
        }
        return try await receiveReport(request)
    }

    public func reports() async throws -> [AgentReport] {
        try await repository.reports()
    }

    /// Sends the report's message, if `shownMessage` and `shownTarget`, as
    /// the view rendered them, are exactly what is stored, and the agent is
    /// still the same and not waiting for an approval. Anything else sends
    /// nothing and says why; the report stays.
    ///
    /// The attempt is recorded before `agent prompt` runs. If the outcome
    /// is then unknown (Herdr ended oddly, or the send could not be
    /// recorded), the record stays and the report can only be dismissed.
    public func acceptReport(_ id: Int64, shownMessage: String, shownTarget: ReportTarget?) async -> AcceptOutcome {
        // One Accept at a time, so a double click cannot send twice.
        guard !acceptingReports.contains(id) else { return .notSent(.alreadyHandled) }
        acceptingReports.insert(id)
        defer { acceptingReports.remove(id) }
        guard let report = try? await repository.report(id), let proposal = report.proposal else {
            return .notSent(.alreadyHandled)
        }
        if report.outcomeUnknown { return .notSent(.outcomeUnknown(name: proposal.target?.label ?? proposal.targetAsGiven)) }
        guard proposal.message == shownMessage, proposal.target == shownTarget else { return .notSent(.changed) }
        guard let target = proposal.target, let agents else { return .notSent(.noTarget) }
        let current = await agents.agents()
        if case .failure(let refusal) = target.check(in: current) { return .notSent(refusal) }
        guard (try? await repository.beginSending(id)) == true else { return .notSent(.failed) }
        defer { Task { await self.broadcast() } }
        let result = await agents.prompt(target.paneID, text: proposal.message, on: target.server)
        switch result {
        case .sent:
            do {
                try await repository.markReportSent(id)
            } catch {
                return .outcomeUnknown(to: target.label)
            }
            return .sent(to: target.label)
        case .unknown:
            return .outcomeUnknown(to: target.label)
        case .blocked, .notFound, .refused:
            // Certain that nothing was sent. If even this can't be saved,
            // the report stays locked, which only costs a new report.
            let refused = try? await repository.sendingRefused(id)
            guard refused != nil else { return .outcomeUnknown(to: target.label) }
            return switch result {
            case .blocked: .notSent(.blocked(name: target.label))
            case .notFound: .notSent(.gone(name: target.label))
            default: .notSent(.failed)
            }
        }
    }

    public func dismissReport(_ id: Int64) async throws {
        try await repository.removeReport(id)
        await broadcast()
    }

    /// The caller pane's agent name as Herdr has it, else its program,
    /// else its pane. `--from` is free text and never takes its place.
    private static func sourceLabel(_ request: ReportRequest, _ agents: HerdrAgents?) -> String {
        guard let pane = request.caller?.paneID else { return "An agent outside Herdr" }
        if case .connected(let server, let list)? = agents, server == request.caller?.server,
           let agent = list.first(where: { $0.paneID == pane }) {
            return agent.name ?? agent.kind
        }
        return pane
    }
}
