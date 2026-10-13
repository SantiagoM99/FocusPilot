# Feature matrix

P0 = first complete focus loop. P1 = first-release enhancements after platform validation. P2 = later, evidence-driven work.

| Capability | Priority | Concrete behavior | Acceptance criterion |
|---|---|---|---|
| Task capture | P0 | Title, project, deadline, importance, estimate, next action | Natural-language date is previewed with timezone before save |
| Task order | P0 | Manual ordering and pinned current task | Agent cannot silently reorder a pinned task |
| Context links | P0 | Existing folders, URLs, resources, Herdr targets | Missing or moved resource produces a repair action |
| Focus session | P0 | Current action, allowed context, duration, break | Session recovers across app restart and sleep without extending an exception |
| Observe-only mode | P0 | Activity and pilot Event metrics without blocking or nudges | Baseline week measurable before blocking is enabled; no URLs or content stored in metrics |
| Safari rules | P0 | Configured sites blocked; timed exception scoped to a domain or exact URL | Allowed/blocked transitions match policy version and expiry |
| Chrome rules | P0 | Same session and policy | Switching browsers does not reset exception duration |
| Connection health | P0 | Show connected, stale, disconnected, permissions missing, unsupported browser or unprotected profile in use | UI never claims full protection when required integration is absent |
| Native surfaces | P0 | Planning window, menu bar, optional focus panel | Keyboard navigation, VoiceOver labels, light/dark, reduced motion |
| Herdr status | P0 | Working/blocked/ready/unknown and output preview | Unknown is not treated as complete; output is not executed |
| Manual navigation | P0 | User selects linked pane or browser resource | Pane focus occurs only after explicit action |
| Wrap-up | P0 | Completed outcome, remaining work, return cue | Next action is saved independently of conversation |
| Local AI accounting | P0, with first model calls | Record usage, request attempts, task attribution and cost basis | Retries counted once each; missing usage is unknown; rollups not double-counted |
| Supervisor budget | P0, with first model calls | Daily admission cap, one request in flight, quiet fallback; reservations only if concurrency is later allowed | Unresolved usage counts at its conservative estimate and is visible; focus remains active |
| New environment | P1 | Preview folder/workspace creation under configured root | Existing files never overwritten; partial failures can be reconciled |
| Priority suggestions | P1 | Explain recommendation using structured inputs | Deadline/state changes invalidate old suggestions |
| Activity lists | P0 | Seeded allowed tools; owner edits allowed/blocked apps and sites in Settings | Seeded tools never trigger check-ins; edits take effect in the next compiled policy |
| Coach | P1 | Low-frequency event-driven check-ins and help with stuck work | Supports relevant activity, switch task, snooze, and break responses |
| Unknown-app check-in | P1, with Coach | Ask the purpose of an unclassified app or site once after grace | Answer saved by scope; no repeat for that app and task; Distraction requires confirmation before blocking |
| Memory inspection | P1 | Edit/delete preferences and summaries | Deleted source also invalidates derived search/cache entries |
| AI Workload view | P1 | Group agent runs by task, urgency, dependencies and measured/estimated usage | Unlinked/unknown usage visible; spend, quota, compute and attention distinct |
| LangSmith diagnostics | P1 | Opt-in asynchronous decision traces and usage export | Metadata-only payloads scrubbed; export outage cannot affect budgets or focus |
| External usage adapters | P1, capability-gated | Import supported agent usage with source and freshness | No claim of automatic Herdr coverage; duplicates/cumulative counters reconciled |
| Urgent-work recommendations | P1 | Suggest defer/interrupt actions with resource rationale | Pinned/dependent work respected; no automatic stopping |
| Explicit turn interruption | P1, capability-gated | Use tool-supported mechanism after preview and fresh identity check | Capability proved; cancellation reconciled; not labelled pause |
| Semantic retrieval | P2 | Search summaries by meaning | Improves retrieval on real queries versus keyword baseline |
| Stronger enforcement | P2 | Evaluate OS-level approach separately | Document supported browsers, privileges, and bypass limits |
| External task imports | P2 | Calendar/academic/task-manager adapters | Source, sync time, conflict handling, timezone retained |
| Agent delegation | P2 | User-defined permitted actions | No approval dialogs answered or destructive commands issued autonomously |
| Provider allowance integration | P2 | Supported quotas and reset times separate from estimates | Opaque subscription limits never converted into invented bills |
| True pause/resume | P2, capability-gated | Tool-supported recovery of interrupted work | Resume behavior demonstrated before exposing control |

P0/P1 are sequencing boundaries within the intended first release, not promises of feasibility before the spikes.
