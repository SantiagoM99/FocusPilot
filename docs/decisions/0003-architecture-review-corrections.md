# Architecture review corrections

Date: 2026-10-13. Status: proposed; pending owner acceptance. Platform behavior marked "validate" is unproven.

Second review of the full design set, including decision 0002. Each finding lists the change made to the documents. Nothing here is a confirmed owner decision until accepted.

## Process, ownership and enforcement

| Finding | Change |
|---|---|
| "Single SQLite writer" is an in-process actor, but the Safari extension handler and Chrome native host are separate processes that may run while the app is quit | Cross-process contract: app publishes a compiled policy snapshot; helpers read it and append to an observation inbox; only the app writes authoritative data ([Architecture](../ARCHITECTURE.md#process-model)) |
| Process ownership after login, window close or quit was undefined | Proposal: one menu-bar-resident process registered as a login item; no separate daemon/XPC agent until a spike requires it |
| Extensions depended on the app for exception/session expiry | Policy carries absolute session end and exception expiries; each extension evaluates it locally on every wake. Behavior without the app follows session mode (confirmed below) |
| DNR cannot close an already loaded page or stop buffered media | Candidate: content script on blocked domains enforces expiry in-page; on activation, existing matching tabs are redirected (validate, especially Safari) |
| Chrome worker lifecycle assumptions were unverified | Recorded documented behavior: 30 s idle termination; an open `connectNative()` port keeps the worker alive (Chrome 105+); alarms ≥30 s, may be late, fire after wake; restart persistence documented from Chrome 150 |
| Engine was described as a component with I/O arrows | Engine is a pure function of state and an injected clock, producing compiled policy and effects; the coordinator delivers them and tracks acknowledgements |
| Unsupported browsers and profiles were an invisible bypass | Activity observer flags unsupported browsers frontmost during a session; acknowledgements are per Chrome profile; incognito/private permission is tracked |
| Diagram contradicted single-writer rule (`USAGE --> DB`, `ENGINE --> BRIDGE`) and omitted named components | Diagram corrected; coordinator named FocusCoordinator to match the architecture review |

## Data model

| Finding | Change |
|---|---|
| Deadline as instant + date-only flag invites midnight-UTC errors | Deadline is either `{localDate, timezone}` or `{instant, timezone}`, plus original text |
| Block rules were session-owned, but blocked sites are durable owner preferences | Split BlockRuleSet (owner-authored), Exception (scope, absolute expiry, shared across browsers) and CompiledPolicy (derived, versioned, acknowledged) |
| Domain-wide exceptions make YouTube all-or-nothing | Exceptions may be scoped to an exact URL as well as a domain |
| Launch set required by workspace rules had no field | `Resource.launchOrder` (null = not in launch set) |
| Pilot metrics had no storage, and 24 h raw retention would erase a baseline | Append-only Event table with aggregated counts/durations, no URLs or content |
| TraceOutbox duplicated ledger data and was listed as authoritative | Export reads ledger rows through a cursor; delivery state is operational, not authoritative |
| Default classification for unknown apps/domains was undefined | Unknown counts as ambiguous and triggers a purpose check-in (confirmed below) |

## AI usage and workload (refines decision 0002)

| Finding | Change |
|---|---|
| P0 accounting included concurrent reservations, cost-estimate versioning and per-task budgets for a call volume likely measured in cents/day | P0: serialized supervisor gateway (concurrency 1), ModelAttempt rows with usage and rate snapshot, daily admission cap. Reservations become necessary only if concurrency rises; per-task budget and urgent reserve move to P1 |
| The workload view's value is in external agents, which initial coverage shows as Unknown | Workload view leads with task, dependency and attention data, which need no token telemetry; usage is a supporting column |
| No concrete external usage source was identified | Claude Code documents OpenTelemetry token/cost metrics with a session ID; recorded as a candidate first adapter requiring a local authenticated OTLP receiver (validate) |
| Bespoke LangSmith REST mapping was the only export path | LangSmith documents OTLP ingestion; recorded as alternative to evaluate |
| Inspected Herdr commands include no interrupt command | Any "Interrupt turn" via Herdr would be input delivery and falls under explicit prompt authority until a dedicated mechanism is proven |
| Usage accounting and LangSmith export were listed as platform spikes | Moved to deterministic logic tests; external usage and interruption remain spikes |

## Product and validation

| Finding | Change |
|---|---|
| A baseline week needs measurement before blocking exists | Observe-only mode added at P0, ordered before blocking in the spike plan |
| Spike order was unspecified | First vertical slice: menu-bar app + Safari extension blocking one site + one timed exception surviving sleep and app quit |

## Open decisions raised

- Which sites are always-on versus scheduled versus session-only (owner configuration, not a design blocker).
- Whether and how to extend focus to the owner's iPhone (Focus mode via Shortcuts, or a companion iOS app using Screen Time APIs); pending owner choice.

## Confirmed by owner

- 2026-10-13: Storage library is GRDB.swift, chosen over SwiftData/Core Data for FTS5 search, WAL concurrent reads, SwiftUI observation and documented multi-process sharing. No dependency is added until implementation starts. See [Data and memory](../DATA_AND_MEMORY.md#storage-library).
- 2026-10-13: Unknown apps and sites count as ambiguous. In Coach mode a deterministic rule (not model confidence) asks their purpose once: For this task / Always fine / Distraction / Ask later. Answers are stored as ActivityClassification; Distraction needs confirmation before blocking. See [Experience](../EXPERIENCE.md#coach-behavior).
- 2026-10-13: When the app cannot update the policy, normal sessions stop blocking at the planned end; strict sessions keep blocking until the app reconnects. Exceptions always expire on time. See [Architecture](../ARCHITECTURE.md#enforcement-ownership).
- 2026-10-13: Some block rules are always active. Rule sets support always, scheduled, or session-only activation; always-on and scheduled rules are enforced by the extensions regardless of app state.

## Sources

- [Chrome service worker lifecycle](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle)
- [chrome.alarms](https://developer.chrome.com/docs/extensions/reference/api/alarms)
- [LangSmith OpenTelemetry tracing](https://docs.langchain.com/langsmith/trace-with-opentelemetry)
- [Claude Code monitoring usage](https://code.claude.com/docs/en/monitoring-usage)
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [GRDB.swift README](https://github.com/groue/GRDB.swift/blob/master/README.md)
