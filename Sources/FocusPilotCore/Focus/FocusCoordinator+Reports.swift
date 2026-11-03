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
        let receipt = try await repository.addReport(request, sourceLabel: Self.sourceLabel(request, current), target: target)
        await broadcast()
        return receipt
    }

    public func reports() async throws -> [AgentReport] {
        try await repository.reports()
    }

    /// Sends the report's message, if `shownMessage` is exactly it and its
    /// agent is still the same and not waiting for an approval. Anything
    /// else sends nothing and says why; the report stays.
    public func acceptReport(_ id: Int64, shownMessage: String) async -> AcceptOutcome {
        // One Accept at a time, so a double click cannot send twice.
        guard !acceptingReports.contains(id) else { return .notSent(.alreadyHandled) }
        acceptingReports.insert(id)
        defer { acceptingReports.remove(id) }
        guard let report = try? await repository.report(id), let proposal = report.proposal else {
            return .notSent(.alreadyHandled)
        }
        guard proposal.message == shownMessage else { return .notSent(.changed) }
        guard let target = proposal.target, let agents else { return .notSent(.noTarget) }
        let current = await agents.agents()
        if case .failure(let refusal) = target.check(in: current) { return .notSent(refusal) }
        switch await agents.prompt(target.paneID, text: proposal.message, on: target.server) {
        case .sent:
            try? await repository.markReportSent(id)
            await broadcast()
            return .sent(to: target.label)
        case .blocked: return .notSent(.blocked(name: target.label))
        case .notFound: return .notSent(.gone(name: target.label))
        case .refused, .failed: return .notSent(.failed)
        }
    }

    public func dismissReport(_ id: Int64) async throws {
        try await repository.removeReport(id)
        await broadcast()
    }

    /// The `--from` name, else the caller pane's agent name, else its pane.
    private static func sourceLabel(_ request: ReportRequest, _ agents: HerdrAgents?) -> String {
        if let from = request.from { return from }
        guard let pane = request.caller?.paneID else { return "An agent outside Herdr" }
        if case .connected(let server, let list)? = agents, server == request.caller?.server,
           let agent = list.first(where: { $0.paneID == pane }) {
            return agent.name ?? agent.kind
        }
        return pane
    }
}
