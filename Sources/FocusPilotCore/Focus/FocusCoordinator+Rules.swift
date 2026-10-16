import Foundation

/// Block rules and the allowed list. Every saved edit gets a new policy
/// revision in the same write and is published right away, compiled with
/// the current session's rules.
extension FocusCoordinator {
    public func ruleSets() async throws -> [BlockRuleSet] {
        try await repository.policyInputs().rules
    }

    public func allowedActivities() async throws -> [AllowedActivity] {
        try await repository.policyInputs().allowed
    }

    public func saveRuleSet(_ rule: BlockRuleSet) async throws {
        try await publish(repository.save(rule))
    }

    public func deleteRuleSet(_ id: Int64) async throws {
        try await publish(repository.deleteRuleSet(id))
    }

    public func allow(_ entry: AllowedActivity) async throws {
        try await publish(repository.allow(entry))
    }

    public func removeAllowed(_ id: Int64) async throws {
        try await publish(repository.removeAllowed(id))
    }

    func publish(_ change: PolicyChange) async {
        await publish(revision: change.revision, inputs: change.inputs,
                      session: session.flatMap(FocusEngine.policy(for:)), at: now())
        await broadcast()
    }

    /// Compiles and wraps one policy, then hands it to the extensions.
    func publish(revision: Int, inputs: PolicyInputs, session: SessionPolicy?, at: Date) async {
        let rules = PolicyCompiler.compile(rules: inputs.rules, allowed: inputs.allowed, session: session)
        let compiled = CompiledPolicy(revision: revision, effectiveAt: at, rules: rules)
        policy = compiled
        await publisher.publish(compiled)
    }
}
