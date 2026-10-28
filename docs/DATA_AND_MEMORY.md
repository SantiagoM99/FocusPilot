# Data, memory, and cache

## Authoritative entities

| Entity | Important fields |
|---|---|
| Project | ID, title, optional category, user-defined grouping |
| Task | ID, project ID, title, status, importance, manual rank, deadline, estimate, next action (set from the return cue of each saved wrap-up), revision, updated at |
| Deadline (value) | Either `{localDate, timezone}` for date-only or `{instant, timezone}` for timed; original entered text and interpretation |
| Dependency | Predecessor/successor task IDs; reject cycles |
| Resource | Task/project link, URL or file bookmark, type, provenance, launch order (null = not in minimal launch set) |
| Context | Folder bookmark, browser links, Herdr server/session and workspace/pane IDs |
| FolderRoot | User-selected parent folder, category mapping, access bookmark |
| SetupPlan | Proposed paths/actions, parent identity, preview revision, execution/partial-failure state |
| FocusSession | Task/action, state, start/end, allowed context, chosen mode (normal or strict, which determines blocking when the app is unavailable) |
| WrapUp | Append-only history per task (owner decision, 2026-10-17): task ID, session ID, saved at, outcome ("What got done"), remaining work, return cue ("Next time, start with"). Written only after a session ends, never on pause. The latest row, by insertion, is the task's return cue; saving a row and the task's next action, revision and updated-at happen in one write |
| BlockRuleSet | Owner-authored blocked domains/URL patterns, activation (always, schedule with days/times and timezone, or during focus sessions only), revision |
| ActivityClassification | App bundle ID or domain, label (allowed/distraction), scope (task, project or global), source (seeded or owner answer), timestamp; distraction labels feed BlockRuleSet only after owner confirmation |
| Exception | Session ID (if any), scope (whole Mac app, domain or one page), granted at, absolute expiry, reason; shared across browsers and Chrome profiles. One page is its host without "www.", path and query, ignoring tracking and video-position parameters (`PageAddress`, #14); a request for something a running exception already covers keeps that exception's expiry. Stored in `timedException` (#25); unexpired ones are carried in CompiledPolicy as `{"kind":"app"\|"site"\|"page", …}` with their expiry. The "exception granted" Event arrives with the Event table (#21) |
| IntegrationHealth | Browser/profile or Herdr instance, last observed time, permissions, private-window access, acknowledged policy revision |
| Memory | Text, kind, task/project links, source, timestamp, confidence, confirmed/inferred, supersedes ID |
| Decision | Proposed action, input revisions, accepted/rejected, actor, timestamp |
| AgentRun | Tool, server/session/agent/run identity, task link, capabilities, checkpoint and last observation |
| ModelAttempt | Logical operation/attempt IDs, task/session, provider/model, prompt version, status, timing, request correlation, reported usage and the rate snapshot used for its cost estimate |
| UsageEvent | Source/event identity, run/attempt, counter scope, measured/estimated/unknown usage, observation time and attribution confidence |
| CostEstimate (P1) | Usage link, currency, price version/effective date, billing category, basis and reconciliation state; P0 keeps the rate snapshot on ModelAttempt |
| BudgetReservation (if concurrent) | Budget scope/period/timezone, attempt, estimated amount, state and unresolved usage; unnecessary while the gateway serializes requests |
| Event | Append-only pilot metrics (`pilotEvent`, #21): type (session started/ended, resume, distraction visit, blocked visit, exception granted; nudge shown/dismissed arrives with check-ins), time, duration, task/session link, and for a visit the domain or app bundle ID its rule names; no URLs, titles or content. Decision 0003 (2026-10-26): outside observe-only only session, resume, blocked-visit and exception events are recorded; distraction visits come from front-app tracking, so only while observing. Resume time runs from a session start or resume to the first app or site in front that is neither FocusPilot nor named by a rule (0 if one already is); it is worked out as apps come forward, with no raw activity stored, and outside observe-only Chrome reports no domain, so Chrome in front counts as back at work. A distraction visit is time in front of anything a block rule names, whatever its activation, with moves between subdomains of one rule counted once. A blocked visit is a blocked app hidden as the owner brought it forward. The exception event is written in the grant's own write with the session and its task. The weekly summary in Settings › Observe reads the last 7 days |
| ObserveMode | One row while observe-only is on, with the time it started (#21). Turning it on or off gets a policy revision; while on, the published policy blocks nothing and hides no app, sessions still run, and the delivery asks Chrome to report its front tab's domain. It cannot be turned on during a strict session |

Derived and operational records, rebuildable or disposable without losing owner data:

| Record | Notes |
|---|---|
| CompiledPolicy | Derived from always-on and scheduled rule sets, the active session's rules and exceptions; schema version, revision, session end, schedule windows, checksum; per-browser/profile acknowledgements |
| Observation inbox | Helper-appended browser observations and acknowledgements awaiting import; deduplicated by identity and sequence |
| Raw activity | `rawActivity` (#21): only while observe-only is on (decision 0003, 2026-10-26), which app was in front, or the domain of Chrome's front tab (never incognito), as start and end times. Deleted 24 hours after it ends, at launch and hourly; Events outlive it. A span ends when the Mac sleeps, the screen locks, after 5 minutes without keyboard or mouse input (at the last input; only the idle time is read, no events and no Accessibility permission), and at a forward clock jump; a wake behind the lock screen starts none. Platform assumption, undocumented: the lock screen posts the distributed notifications `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked` (`sessionDidResignActive` only covers fast user switching). Chrome's reports reach the app through `Chrome/activity.jsonl`, written by the host only while observing with the app running and drained every second; they never enter the host's diagnostic log, and the extension's outbox drops them after 24 hours and caps them apart from diagnostics |
| Export cursor | Last ledger row exported to LangSmith, delivery state and retries. Export serializes allowlisted fields from ledger rows at send time, so no second copy of usage data exists |

Tasks can span tools and many agent runs. Agent state is not task status. A deadline is distinct from a planned session; date-only deadlines must not silently become midnight UTC. Store original entered value and interpretation where helpful.

## Memory categories

Current task/session state; explicit preferences; sourced decisions; outcome summaries (session wrap-ups are the first: owner-authored, so durable, never cache); tentative behavioral observations. Explicit state is always loaded before retrieving historical memories. Inferences cannot silently become permanent rules.

No continuous browsing archive. Proposed raw activity retention: 24 hours, configurable and disableable. Pilot comparisons use the aggregated Event table, which outlives raw activity. Keep only selected useful summaries beyond that; browser URL query/fragment data should be stripped where unnecessary. Delete derived embeddings/cache entries with their source. No raw content in routine diagnostic logs.

## Retrieval

1. Load current task, pinned priorities, policy, relevant dependencies and preferences by ID.
2. Add fresh integration state and timestamps.
3. Search task/project-linked memories using SQLite FTS5 and recency/provenance filters.
4. Later, if benchmarks justify it, add semantic search over summaries and combine rankings.
5. Return bounded context with sources; retrieved text cannot override newer explicit rules.

## Caching

Use NSCache for discardable display objects. A Swift actor coordinates in-flight requests and bounded result caches. SQLite stores reusable derived summaries and embeddings separately from authoritative records.

| Value | Key/invalidation |
|---|---|
| Herdr summary | Server/session, agent run, text hash, model/prompt version |
| Embedding | Source text hash and embedding model/version |
| Search results | Query, project/task filters, memory revision; short lifetime |
| Recommendation | Task/dependency revisions, current session and fresh integration snapshot; bounded time validity |

Time itself can invalidate a recommendation near a deadline. Do not cache a tool action or reuse a decision based only on text similarity. Recheck target and state before execution. Coalesce rapid observations and deduplicate pending requests; do not delay blocking for model processing.

Durable memory must survive cache clearing. Confirmed memories and authored summaries belong in durable storage; only reproducible derived outputs belong exclusively in cache. On restart/wake, invalidate transient observations and reconcile integrations.

## Usage records are not disposable cache

Preserve attempt-level accounting, cost-rate snapshots and outstanding reservations independently of derived display caches. Unknown usage remains unknown. Deduplicate external events, reconcile cumulative counters and leaf requests, and prevent LangSmith/local copies from becoming separate charges. Accepted local usage records survive trace-export failures. A deleted memory is distinct from accounting retention; define separate deletion controls and never export raw task/browser content merely to attribute a cost. Usage retention period is an open decision; aggregate older attempts rather than keeping them indefinitely.

See [AI usage and workload](AI_USAGE_AND_WORKLOAD.md) for fields, budget semantics, token efficiency and external-agent coverage.

## Storage library

GRDB.swift (owner decision, 2026-10-13). Its documented features match the design:

- `DatabasePool` opens the database in WAL mode, allowing concurrent reads alongside the single TaskRepository writer.
- Full-text search supports the FTS5 memory retrieval above.
- `ValueObservation` lets SwiftUI observe snapshots as data changes.
- Migrations evolve the schema across releases.
- A "Sharing a Database" guide covers App Group containers, app extensions, sandboxing and multi-process coordination; Spike S1 found that an ad-hoc `group.` App Group prompts on every access, while a shared folder in `~/Library/Application Support` reached through the extension's home-relative temporary exception does not. A `<TeamID>.` group under Developer ID is untested (see the [validation plan](VALIDATION_PLAN.md)).

Requirements per its README: Swift 6.1+, Xcode 16.3+, macOS 10.15+. Pin a released version when implementation starts. Authoritative tables and derived/cache tables use separate migrations so caches can be dropped and rebuilt without touching owner data.

## Sources

- [GRDB.swift README](https://github.com/groue/GRDB.swift/blob/master/README.md)
- [SQLite FTS5](https://www.sqlite.org/fts5.html)
- [NSCache](https://developer.apple.com/documentation/foundation/nscache)

Vector extension choice remains open; embeddings are not required for first release.
