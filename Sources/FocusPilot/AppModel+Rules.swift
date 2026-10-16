import FocusPilotCore

/// Block rules and the allowed list as Settings uses them. The coordinator
/// validates, saves and publishes; this keeps the lists Settings shows.
extension AppModel {
    func loadRules() async {
        guard let coordinator else { return }
        do {
            ruleSets = try await coordinator.ruleSets()
            allowed = try await coordinator.allowedActivities()
        } catch {
            rulesError = "Could not load rules: \(error.localizedDescription)"
        }
    }

    /// Saves a new or edited rule set. Returns false, with `rulesError`
    /// set, if it was refused.
    @discardableResult
    func save(_ rule: BlockRuleSet) async -> Bool {
        await edit { try await $0.saveRuleSet(rule) }
    }

    func deleteRuleSet(_ id: Int64) async {
        await edit { try await $0.deleteRuleSet(id) }
    }

    @discardableResult
    func allow(_ entry: AllowedActivity) async -> Bool {
        await edit { try await $0.allow(entry) }
    }

    func removeAllowed(_ id: Int64) async {
        await edit { try await $0.removeAllowed(id) }
    }

    private func edit(_ change: (FocusCoordinator) async throws -> Void) async -> Bool {
        guard let coordinator else { return false }
        do {
            try await change(coordinator)
            rulesError = nil
        } catch let error as RuleError {
            rulesError = RuleErrorText.message(error)
            return false
        } catch {
            rulesError = "Could not save: \(error.localizedDescription)"
            return false
        }
        await loadRules()
        return true
    }
}
