# AI observability and workload management

Date: 2026-10-13. Status: accepted direction; adapters and integrations require validation.

## Owner intent

Track AI usage to optimize consumption and identify processes that can be deferred or interrupted to prioritize urgent work. LangSmith, rather than LangGraph, was the intended observability product.

## Decisions

- Keep native Swift orchestration. No LangGraph runtime in the initial design.
- Add a local SQLite usage ledger, per-request model gateway, budget admission and native AI Workload view.
- Add optional LangSmith diagnostics without making local budget/focus behavior depend on exports.
- Start with FocusPilot calls; external Herdr-agent telemetry needs individual validated adapters.
- Keep spend, provider allowance, local compute and human attention separate.
- External controls are explicit and capability-gated. Defer, interrupt and stop are different; never claim reliable pause without evidence.
- Token efficiency comes primarily from avoiding calls and bounding context. Provider prompt caching is an additional optimization.

## Tradeoffs

A native REST exporter preserves the single Swift runtime but requires implementing and testing async delivery, retries and schema mapping. Provider usage is incomplete in some failures and external tools; unknown and estimated values must be visible. A local admission budget cannot promise a hard ceiling on external bills.

## Scope

P0: local accounting for model calls when introduced, basic usage/budget view. P1: optional LangSmith, workload recommendations, selected external usage adapters and validated explicit interruption. P2: broader quota integrations and true pause/resume where supported. Generic process termination remains outside the first release.

See [AI usage and workload](../AI_USAGE_AND_WORKLOAD.md) for the full specification. [Decision 0003](0003-architecture-review-corrections.md) adopts a smaller P0 (serialized gateway, daily cap, no reservations), an export cursor instead of a trace outbox, and a workload view led by task structure; accepted by the owner on 2026-10-13.
