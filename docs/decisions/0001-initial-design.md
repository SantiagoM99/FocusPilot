# Initial decisions

Date: 2026-10-13. Status: accepted direction with unvalidated implementation details.

## Confirmed from owner

- Mac-only, visually pleasing native feel.
- Safari primary, Chrome occasional.
- Multiple tasks/agents in Herdr; desktop-wide assistant needed.
- Prioritization, next actions, and Instagram/YouTube blocking are core.
- Active supervisor is desired.
- Respect existing top-level folder layout; reuse workspaces and create new ones when appropriate.
- Start with documentation/design and independent skeptical agent review.
- Project belongs under Projects/Personal.
- Token-efficient supervisor and usage visibility are desired; use local accounting with optional LangSmith diagnostics.
- Link AI workload to urgent task prioritization, with explicit controls and truthful external telemetry limits.

## Proposed technical direction

SwiftUI/AppKit, local SQLite, browser-specific extension bridges, Herdr adapter, deterministic focus engine, bounded event-driven model. Structured memory and keyword search precede vector retrieval. Small local caches; no separate cache server.

[Decision 0002](0002-ai-observability-and-workload.md) adds native model orchestration, a local usage ledger/budgets, optional LangSmith and capability-gated workload management. LangGraph is not adopted.

[Decision 0003](0003-architecture-review-corrections.md) proposes process-model, enforcement-ownership and data-model corrections from a second review; pending owner acceptance.

## Open decisions

- Final product name (FocusPilot is a working name).
- Minimum supported OS/browser versions; validate provisional Developer ID direct distribution.
- Model provider/local model choice, costs, opt-in context scope.
- Exact root/category mappings and workspace templates.
- Background helpers and extension transport after spikes.
- Whether strict blocking needs stronger enforcement later.
- Coaching frequency after pilot.
- External usage sources, tool-specific interruption capabilities, budget defaults and Swift LangSmith exporter validation.

## Review dispositions

Accepted changes from independent reviews: reliable quiet loop before proactive coaching; minimal task capture and launch set; explicit priority remains authoritative; separate browser transports with policy acknowledgements; one SQLite writer; distribution and expiry spikes before broad implementation; typed model proposals with revision checks; no claims of activity-based progress inference or tamper resistance. See both review documents for criticism-to-design dispositions.
