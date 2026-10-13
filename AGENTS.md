# Working on FocusPilot

Read README.md and the relevant design documents before editing. This project is in design phase. Do not introduce an implementation framework or application scaffold unless requested.

- Preserve user-configured folder boundaries. Never reorganize unrelated projects.
- Distinguish confirmed decisions, proposals, and platform assumptions requiring validation.
- Treat deadlines, priorities, current focus, and block policies as structured state, not inferred conversation memory.
- AI proposes changes; deterministic code validates authority and executes authorized actions.
- No autonomous prompts to other Herdr agents, approvals, pane closure, or focus changes by default.
- Native macOS interface: SwiftUI/AppKit. Safari first, with Chrome supported.
- Cache derived values only; clearing caches must not remove tasks, preferences, deadlines, or focus rules.
- Preserve usage provenance and uncertainty; external Herdr agents are not automatically instrumented. Do not double-count request events, cumulative counters, or trace rollups.
- Native Swift orchestration; LangSmith is optional diagnostics, not the authoritative budget ledger. No LangGraph runtime is selected.
- Budget exhaustion never stops external agents automatically. Expose interruption only after capability validation; never label it pause without proven recovery.
- Use primary platform documentation for technical claims and record sources.
- Independent skeptical review is useful when explicitly requested; record findings and dispositions.
- Avoid adding unrelated dependencies or writing brittle tests for design documents.

## Agent skills

### Issue tracker

GitHub Issues in the private `SantiagoM99/FocusPilot` repo, via `gh`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five labels (needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` glossary at the root (created when terms get resolved) and decision records in `docs/decisions/`. See `docs/agents/domain.md`.
