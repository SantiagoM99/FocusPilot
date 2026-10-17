import Foundation

/// Block rules and the allowed list. Every saved edit gets a new policy
/// revision in the same write and is published right away, compiled with
/// the current session's rules.
///
/// During a strict session, an edit that weakens a rule (decision 0003,
/// 2026-10-17) first returns `needsConfirmation`, then waits
/// `StrictEarlyEnd.wait` from the confirmation, like ending early. Adding or
/// tightening rules is immediate.
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
        try await publish(repository.allow(entry))
    }

    public func removeAllowed(_ id: Int64) async throws {
        try await publish(repository.removeAllowed(id))
    }

    private var strictRulesApply: Bool {
        guard let session, !session.hasEnded else { return false }
        return session.mode == .strict
    }

    private func perform(_ edit: RuleEdit, confirmed: Bool) async throws -> RuleEditOutcome {
        guard strictRulesApply else {
            try await publish(apply(edit, allowWeakening: true))
            return .saved
        }
        if let wait = ruleWait, wait.request == edit {
            let availableAt = availableAt(wait)
            if now() < availableAt { return .waitUntil(availableAt) }
            ruleWait = nil
            try await publish(apply(edit, allowWeakening: true))
            return .saved
        }
        do {
            try await publish(apply(edit, allowWeakening: false))
            return .saved
        } catch RuleError.weakensStrictSession {
            guard confirmed else { return .needsConfirmation }
            let wait = StrictWait(request: edit, confirmedAt: uptime())
            ruleWait = wait
            await broadcast()
            return .waitUntil(availableAt(wait))
        }
    }

    private func apply(_ edit: RuleEdit, allowWeakening: Bool) async throws -> PolicyChange {
        switch edit {
        case .save(let rule): try await repository.save(rule, allowWeakening: allowWeakening)
        case .delete(let id): try await repository.deleteRuleSet(id, allowWeakening: allowWeakening)
        }
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
        await publisher.publish(compiled)
    }
}
