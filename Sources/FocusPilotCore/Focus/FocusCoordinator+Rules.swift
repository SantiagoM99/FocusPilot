import Foundation

/// Block rules and the allowed list. Every saved edit gets a new policy
/// revision in the same write and is published right away, compiled with
/// the current session's rules.
///
/// During a strict session, an edit that weakens a rule (decision 0003,
/// 2026-10-17) first returns `needsConfirmation`, then waits
/// `StrictEarlyEnd.wait` from the confirmation, like ending early. Adding or
/// tightening rules is immediate. A confirmed change applies only to the rule
/// as it was confirmed, within `StrictEarlyEnd.applyWindow` after the wait,
/// and any other edit drops it.
extension FocusCoordinator {
    public func ruleSets() async throws -> [BlockRuleSet] {
        try await repository.policyInputs().rules
    }

    public func allowedActivities() async throws -> [AllowedActivity] {
        try await repository.policyInputs().allowed
    }

    @discardableResult
    public func saveRuleSet(_ rule: BlockRuleSet, confirmed: Bool = false) async throws -> RuleEditOutcome {
        try await perform(.save(rule), confirmed: confirmed)
    }

    @discardableResult
    public func deleteRuleSet(_ id: Int64, confirmed: Bool = false) async throws -> RuleEditOutcome {
        try await perform(.delete(id), confirmed: confirmed)
    }

    /// The owner changed their mind about a weakening rule change.
    public func cancelRuleEdit() async {
        ruleWait = nil
        await broadcast()
    }

    /// Allowing is never weakening: a blocked or overlapping target is refused.
    public func allow(_ entry: AllowedActivity) async throws {
        try await commit(repository.allow(entry))
    }

    public func removeAllowed(_ id: Int64) async throws {
        try await commit(repository.removeAllowed(id))
    }

    private var strictRulesApply: Bool {
        guard let session, !session.hasEnded else { return false }
        return session.mode == .strict
    }

    private func perform(_ edit: RuleEdit, confirmed: Bool) async throws -> RuleEditOutcome {
        guard strictRulesApply else {
            try await commit(apply(edit, revision: nil, allowWeakening: true))
            return .saved
        }
        if let wait = ruleWait, wait.hasExpired(at: uptime()) {
            ruleWait = nil
            await broadcast()
        }
        if let wait = ruleWait, wait.request.edit == edit {
            let availableAt = availableAt(wait)
            if now() < availableAt { return .waitUntil(availableAt) }
            ruleWait = nil
            do {
                try await commit(apply(edit, revision: wait.request.ruleRevision, allowWeakening: true))
            } catch {
                await broadcast()
                throw error
            }
            return .saved
        }
        do {
            try await commit(apply(edit, revision: nil, allowWeakening: false))
            return .saved
        } catch RuleError.weakensStrictSession {
            guard confirmed else { return .needsConfirmation }
            let confirmedEdit = ConfirmedRuleEdit(edit: edit, ruleRevision: try await storedRevision(of: edit))
            let wait = StrictWait(request: confirmedEdit, confirmedAt: uptime())
            ruleWait = wait
            await broadcast()
            return .waitUntil(availableAt(wait))
        }
    }

    /// A save already carries the revision it was made from; a delete is
    /// pinned to the rule as stored when the owner confirmed it.
    private func storedRevision(of edit: RuleEdit) async throws -> Int? {
        switch edit {
        case .save(let rule): rule.revision
        case .delete(let id): try await repository.policyInputs().rules.first { $0.id == id }?.revision
        }
    }

    private func apply(_ edit: RuleEdit, revision: Int?, allowWeakening: Bool) async throws -> PolicyChange {
        switch edit {
        case .save(let rule): try await repository.save(rule, allowWeakening: allowWeakening)
        case .delete(let id): try await repository.deleteRuleSet(id, revision: revision, allowWeakening: allowWeakening)
        }
    }

    /// A pending weakening change was confirmed against the lists before
    /// this edit, so the edit drops it.
    private func commit(_ change: PolicyChange) async {
        ruleWait = nil
        await publish(change)
    }

    /// The waiting rule change, unless its apply window has passed.
    func pendingRuleEdit() -> PendingRuleEdit? {
        guard let wait = ruleWait, !wait.hasExpired(at: uptime()) else { return nil }
        return PendingRuleEdit(edit: wait.request.edit, availableAt: availableAt(wait),
                               expiresAt: now().addingTimeInterval(wait.untilExpiry(at: uptime()) / .seconds(1)))
    }

    func publish(_ change: PolicyChange) async {
        await publish(revision: change.revision, inputs: change.inputs,
                      session: session.flatMap(FocusEngine.policy(for:)), at: now())
        await broadcast()
    }

    /// Compiles and wraps one policy, then hands it to the extensions. The
    /// policy Settings shows only moves forward: an edit that interleaved
    /// with a newer one is still published (extensions drop it by revision)
    /// but never replaces the newer one here.
    func publish(revision: Int, inputs: PolicyInputs, session: SessionPolicy?, at: Date) async {
        let rules = PolicyCompiler.compile(rules: inputs.rules, allowed: inputs.allowed, session: session)
        let compiled = CompiledPolicy(revision: revision, effectiveAt: at, rules: rules)
        if compiled.revision > policy?.revision ?? 0 {
            policy = compiled
        }
        await publisher.publish(PolicyDelivery(policy: compiled, focus: compiled.session == nil ? nil : await focusContext(),
                                               source: repository.policySource))
    }

    /// The session's task for the blocked page, with the Now task's next
    /// step and project when it is still the same task.
    private func focusContext() async -> FocusContext? {
        guard let session else { return nil }
        let task = (try? await repository.nowTask()).flatMap { $0?.id == session.taskID ? $0 : nil }
        return FocusContext(title: session.action, nextAction: task?.nextAction, projectTitle: task?.projectTitle)
    }
}
