import FocusPilotCore

/// Block rules and the allowed list as Settings uses them. The coordinator
/// validates, saves and publishes; this keeps the lists Settings shows.
extension AppModel {
    func loadRules() async {
        guard let coordinator else { return }
        do {
            ruleSets = try await coordinator.ruleSets()
            activityTracker.classify(rules: ruleSets)
            allowed = try await coordinator.allowedActivities()
        } catch {
            rulesError = "Could not load rules: \(error.localizedDescription)"
        }
    }

    /// Saves a new or edited rule set. Returns false, with `rulesError`
    /// set, if it was refused. A change that weakens a strict session asks
    /// for confirmation on the Blocking tab instead; that still returns true.
    @discardableResult
    func save(_ rule: BlockRuleSet) async -> Bool {
        await perform(.save(rule), confirmed: false)
    }

    func deleteRuleSet(_ id: Int64) async {
        await perform(.delete(id), confirmed: false)
    }

    /// Sends a rule change, confirmed or not, and records whether it now
    /// needs confirmation. The countdown comes from the snapshot.
    @discardableResult
    func perform(_ ruleEdit: RuleEdit, confirmed: Bool) async -> Bool {
        var outcome: RuleEditOutcome?
        let succeeded = await edit {
            switch ruleEdit {
            case .save(let rule): outcome = try await $0.saveRuleSet(rule, confirmed: confirmed)
            case .delete(let id): outcome = try await $0.deleteRuleSet(id, confirmed: confirmed)
            }
        }
        ruleEditToConfirm = outcome == .needsConfirmation ? ruleEdit : nil
        return succeeded
    }

    func cancelRuleEdit() async {
        ruleEditToConfirm = nil
        await coordinator?.cancelRuleEdit()
    }

    @discardableResult
    func allow(_ entry: AllowedActivity) async -> Bool {
        await edit { try await $0.allow(entry) }
    }

    func removeAllowed(_ id: Int64) async {
        await edit { try await $0.removeAllowed(id) }
    }

    @discardableResult
    private func edit(_ change: (FocusCoordinator) async throws -> Void) async -> Bool {
        guard let coordinator else { return false }
        do {
            try await change(coordinator)
            rulesError = nil
        } catch let error as RuleError {
            rulesError = RuleErrorText.message(error)
            // Show the rule as it is now, so the owner can check it.
            if error == .ruleChanged { await loadRules() }
            return false
        } catch {
            rulesError = "Could not save: \(error.localizedDescription)"
            return false
        }
        await loadRules()
        return true
    }
}
