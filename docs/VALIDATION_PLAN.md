# Validation before implementation

## Platform spikes (release blocking)

| Spike | Evidence needed | Fallback |
|---|---|---|
| Safari messaging | Running app ↔ extension handler roundtrip; packaging, sandbox/App Group behavior, UI closed | Reduce to explicit app-open requirement with honest state |
| Chrome transport | Registered native host, authenticated/allowlisted sender, app lifecycle | Separate signed helper, subject to distribution review |
| Browser rules | Instagram/YouTube including existing tabs; content-script expiry for loaded pages and buffered media; URL-scoped exceptions; rule acknowledgement per Chrome profile, private mode limits, reconnect | Document unsupported cases; do not claim protection there |
| Exception expiry | Policy evaluated by the extension alone: sleep/wake, worker suspension, app quit, browser restart; no unintended extension of duration | Conservative blocking until reconciled |
| Cross-process state | Helpers read policy snapshot and append observations while the app is quit; App Group access for Developer ID app and sandboxed Safari extension | App-open requirement with honest state |
| Herdr access | External native app can select session, list/read agents, focus explicit pane; distribution sandbox compatible | Read-only/manual linking until solved |
| Folder access | User-selected roots, bookmark persistence, moved folders, collisions/symlinks | Explicit user re-selection and repair |
| Lifecycle | Close window vs quit, restart session restoration, stale observations | No live-state assumptions on recovery |
| iPhone signal | Mac turns a synced Focus on/off via the shortcuts tool; iPhone open/close automations run without confirmation, check the Focus, show the current action, optionally return to the Home Screen and append to an iCloud Drive file; sync delay measured | Phone nudge unavailable; Opal alone covers the phone |
| Unsupported browsers | Detect other browsers or unprotected profiles frontmost during a session | Degraded state shown; no coverage claim |
| External usage | Documented source formats (first candidate: Claude Code OpenTelemetry metrics via an authenticated local receiver), run attribution, cumulative counter resets and overlap with exports | Unavailable/unattributed; no invented total-computer spend |
| Agent interruption | Fresh identity/state, supported interrupt mechanism (none in inspected Herdr commands), checkpoint/resumption and child process behavior | Manual navigation; no pause or generic termination claims |

Usage accounting and the LangSmith exporter are deterministic logic with no platform unknowns except provider counter semantics and the chosen transport (REST or OTLP); cover them with the correctness scenarios below rather than spikes.

Proposed spike order: (1) vertical slice: menu-bar login-item app + Safari extension blocking Instagram + one timed exception that survives sleep and app quit; (2) the same slice in Chrome with content-script expiry; (3) observe-only metrics so the baseline week can start; (4) Herdr access from a GUI app; (5) folder bookmarks and provisioning; (6) external usage and interruption.

Validate the proposed Developer ID direct distribution route, including Safari signing, and choose minimum macOS, Safari and Chrome versions after these tests. Test native-host app relocation/update, permissions revoked, and baseline energy use while idle. Do not build the full supervisor around unproven transports.

## Product experiments

Baseline week followed by a two-week pilot alternating comparable Quiet and Coach sessions. The baseline requires an observe-only mode (activity and Event metrics, no blocking or nudges), so it must exist before blocking is enabled. Start with blocking + chosen next action, then introduce coach check-ins to isolate their value.

Proposed measures: task capture under 30 seconds for simple tasks; resume context within 15 seconds when integrations are healthy; median task upkeep under 5 minutes/day; fewer unplanned distraction visits; useful versus unwanted check-ins; completed deliverables. Thresholds require pilot calibration.

If coach messages are mostly dismissed, reduce triggers and improve next-action support. If task maintenance exceeds benefits, simplify capture and context attachment before adding integrations.

## Correctness scenarios

- Relative deadline with Bogotá timezone; date-only deadline; DST elsewhere; past deadline.
- Priority changes while recommendation is pending; stale result rejected.
- Agent finishes but task needs human review; unknown never means done.
- Pane closed/reused, agent renamed, different server with same ID.
- Extension disabled, permissions revoked, unacknowledged policy.
- Browser switching retains shared exception deadline.
- A blocked site is already open as an SPA; browser reconnect after exception expiry.
- Model unavailable: timers/blocking/tasks continue; no repeated retries storm.
- Prompt injection in assignment/page/agent output cannot execute tool actions.
- Memory deletion removes derived retrieval entries.
- Provisioning interruption produces recoverable partial state without overwriting anything.
- App crashes mid-session: in a normal session extensions keep blocking until the planned end, then stop without the app; in a strict session they keep blocking until the app reconnects; exceptions expire on time in both.
- Unknown app or site during Coach: one check-in after the grace period; the saved answer suppresses repeat questions for that app in that scope; seeded tools never trigger a question; no question while the owner is typing.
- Date-only deadline never acquires an implicit time; timed deadline keeps its timezone.
- Second supervisor request waits while one is in flight (P0); once concurrency is allowed, two concurrent model requests reserve the same budget period without double allocation.
- Interrupted stream with missing usage remains unresolved rather than free; reservations survive restart.
- Cached/reasoning token subsets do not double-count totals; retries have unique attempt records.
- External cumulative usage resets; duplicate local/LangSmith request telemetry; stale and unknown sources.
- Subscription allowance is displayed separately from an API-equivalent estimate and actual bills.
- LangSmith outage/retries do not block UI or local admission; disabling export clears pending uploads.
- Metadata-only payloads exclude task text, URLs, paths, secrets and private free-form errors; remote deletion failure is visible.
- Urgent-task recommendation protects dependencies and identifies which bottleneck stopping work would address.
- Interruption fails or times out after delivery; read actual state before retrying; shell/remote jobs may still run.

## Design review

Sketch native planning, focus, blocked page, setup preview, and disconnected states. Validate keyboard/accessibility behavior. Only implement a vertical slice after the platform and authority boundaries are concrete.
