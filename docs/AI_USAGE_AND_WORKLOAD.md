# AI usage, efficiency, and workload management

Status: design specification. No usage collector, LangSmith connection, budget enforcement, or process-control capability has been implemented.

## Purpose

Help the owner understand AI consumption and decide which jobs to defer or interrupt when an urgent task needs resources or attention. Token spend, provider allowance, local compute, and human attention are separate constraints. Stopping an unrelated remote agent can save spend without accelerating the urgent task.

## Two observability layers

1. **Local usage ledger and native dashboard:** authoritative records for FocusPilot request admission, budgets, and the owner's view. Stored in SQLite; useful without LangSmith. Costs are estimates unless the source supplies a billed amount.
2. **Optional LangSmith export:** inspect decision traces, model calls, latency, failures, and feedback. Disablement or an export outage never disables tasks, blocking, or the local ledger. Export requires opt-in; no account has been connected by this design.

Native Swift actors/state machines orchestrate the supervisor. LangGraph is not required or adopted. LangSmith documents REST tracing; prototype a Swift URLSession exporter with bounded asynchronous sending. Its documentation recommends Python/TypeScript SDKs for their batching/background optimizations, so a native exporter must prove those operational properties itself. Do not assume an official Swift SDK.

## Capture and attribution

All FocusPilot model requests pass through a ModelGateway. Assign a logical operation ID and a distinct attempt ID for each actual provider request. Record task/project, focus session, operation type, provider/account, model, prompt version, input revisions, timestamps, latency, status, and request correlation ID when available.

Record provider-reported input/output usage and supported breakdowns such as cached input, cache writes, or reasoning tokens. Preserve their provider-specific meanings: subsets must not be added to totals twice. Missing counters remain unknown rather than zero. Retain original numeric usage metadata with normalized fields for auditing, without persisting raw prompts by default.

Every usage event identifies source, source event ID, scope, observed time, measured/estimated/unknown status, and attribution confidence. Deduplicate by source event ID. For cumulative counters, store snapshot revisions and derive positive deltas within the same run; detect resets. Never sum a cumulative counter and its constituent request events.

Parent trace totals are rollups; only leaf request usage contributes to the ledger. Retries are distinct attempts and may each incur cost. A local result-cache hit records an avoided request, not fabricated provider token usage or a guaranteed saving.

## External agents in Herdr

Herdr provides execution state and terminal output; it is not assumed to provide token accounting. Agent-specific adapters may consume documented local usage records, explicit telemetry hooks, or provider exports with user authorization. Inventory support before choosing adapters.

Link agent runs to tasks using server/session identity, pane/agent identity, and run ID. Prompt text similarity or terminal output length cannot establish token consumption. Unlinked usage belongs in an unattributed bucket. Unsupported tools, accounts, or metrics show unavailable/unknown with a last-observed time.

LangSmith will observe requests we instrument or integrations explicitly configured to export; it does not automatically observe every agent in Herdr. If the same request appears in a local record and LangSmith, reconcile by correlation ID rather than counting it twice. Ambiguous duplicates remain excluded from confirmed totals pending reconciliation.

Initial coverage: FocusPilot's own calls. External agent usage is a capability-gated addition. Never advertise total-computer AI spend if only some sources are connected.

Candidate first adapter: Claude Code documents OpenTelemetry metrics (`claude_code.token.usage` by input/output/cacheRead/cacheCreation, and `claude_code.cost.usage` in USD) with a `session.id` attribute, enabled by `CLAUDE_CODE_ENABLE_TELEMETRY=1`. Consuming it needs a local OTLP receiver that authenticates its sender (e.g. a header token) and maps `session.id` to a Herdr run; validate in the external-usage spike. Its cost metric is the tool's own estimate, not a bill.

## Cost and allowance semantics

Cost records include currency, price-table version/effective date, billing category, cost basis, and measured/estimated/unknown status. Snapshot the rates used for each estimate. Provider-reported billed amounts can reconcile estimates later without creating duplicate usage.

Subscription coding agents may have included allowances or opaque limits rather than a marginal per-token charge. Show reported allowance/reset time where available; otherwise show unknown. A hypothetical API-equivalent estimate must be labelled separately and never presented as the actual subscription bill.

Estimated spend trends require sufficiently recent comparable samples. No projected completion cost or time without supporting data. Display coverage alongside totals, e.g. measured sources and unknown agents; illustrative UI numbers are not real measurements.

## Token efficiency

- Local event filters handle blocking, clocks, and routine reminders without model calls.
- Coalesce rapid observations and trigger reasoning only on meaningful events or explicit requests.
- ContextBuilder supplies current structured state, relevant changes, and bounded retrieved memories. It does not replay entire chat/browser/terminal histories.
- Summarize completed output once; reuse by run/output hash, scrubbed input, model and prompt version.
- Prefer direct queries and stable templates for factual status messages.
- Ask for short typed proposals and expand explanations on request.
- Evaluate a smaller model for extraction/summaries and a stronger model for difficult planning; measure quality before routing automatically.
- Arrange stable instructions before variable context for provider prompt caching when eligible. Cache savings affect pricing/processing, not the need to bound context.
- Enforce per-operation limits, bounded retries and concurrency. Interrupted or failed requests can still be billable; account for them.

Token/context ceilings and model routing remain configurable hypotheses until measured. Efficiency metrics include calls avoided, reported cache hits, spend by operation, accepted suggestions, irrelevant nudges, and useful outcomes per call. Usage is not a productivity score.

## Budgets

Budget scopes: supervisor daily budget (P0); per-task optional budget and user-defined reserve for urgent tasks (P1). Distinguish warning-only soft limits from admission limits on new FocusPilot requests. A budget is not a guaranteed provider billing cap.

Proposed P0: the gateway admits one supervisor request at a time, records its usage and rate snapshot on completion, and checks the next request against the daily cap. Interrupted or usage-less attempts count at their conservative estimate until reconciled. The reservation scheme below applies once concurrent requests are allowed.

Before a request, atomically reserve estimated cost including an output limit and supported reasoning/cache cost categories. Concurrent requests share reservations. Reconcile actual usage on completion. For interrupted streams or missing usage, retain a conservative unresolved reservation until reconciliation or explicit review; do not silently record zero or release it as free.

Reject optional calls that exceed the available budget and use deterministic quiet behavior. Allow an explicit owner override. Already admitted calls, delayed billing and uncertain usage may exceed estimates; show this uncertainty. Budget exhaustion never disables blocking or discards tasks and never automatically kills external agents.

External-agent budgets are advisory unless the relevant tool exposes a validated control mechanism. Provider quotas/rate limits and subscription allowances are shown separately from dollar budgets. Any prediction that stopping a process speeds up urgent work must identify the shared bottleneck and evidence.

## AI Workload view

The view leads with what needs no telemetry: which runs serve which task, dependencies on the current action, and which runs await the owner's attention. Usage is supporting evidence; while external sources are unconnected, most rows show Unknown and recommendations rely on task structure.

Display a global summary with period/timezone, known spend, unresolved usage, coverage, budget/reservations and disconnected sources. Group runs by task, with an unattributed section. Each row includes:

- Task priority, deadline, dependency relation and current selected action.
- Agent/tool, run identity, state, last observation and latest checkpoint if available.
- Tokens/allowance/estimated cost with source and measurement quality.
- Supported controls and what interruption may lose.
- Recommendation with rationale: frees spend, local compute, attention, or a documented shared quota.

Example: keep the baseline experiment running because it unblocks tonight's report; defer the next application-research job; offer interruption of an unrelated active turn only after checking its current state. Neither past spend nor an agent completion alone determines priority.

## Controls and authority

| Action | Meaning | First-release boundary |
|---|---|---|
| Defer | Do not admit the next queued FocusPilot job | Explicit action; does not stop active work or affect unmanaged queues |
| Interrupt turn | Use a tool's supported mechanism to interrupt current agent work | Explicit confirmation after a fresh state/identity check; capability-gated. Inspected Herdr commands include no interrupt; input delivered through Herdr counts as a prompt |
| Stop process | Terminate execution; may lose work or leave child processes | Manual guidance initially; no generic kill capability in first release |
| Pause/resume | Genuine tool-supported suspension and recovery | Only expose if demonstrated; interruption is not pause |

No automatic process stopping, answering agent approvals, closing panes, or cancelling external work when a budget is reached. A pending control decision carries task/run revisions; stale targets are rejected. Cancellation of an agent does not prove its shell jobs or remote tasks stopped. Reconcile observed state after any action, including failure/timeout; do not blindly repeat input.

## LangSmith export boundary

One trace per supervisor decision, with child spans for context retrieval, model attempts, proposal validation and outcome. Export pseudonymous identifiers, allowlisted numeric usage, operation type, timing, revision metadata and feedback by default. Task titles, file paths, URLs, full prompts, terminal output, free-form feedback and error strings can contain private data and are excluded or locally scrubbed. Credentials remain in Keychain.

Content tracing is a separate explicit opt-in, scoped and revocable. Export reads ledger rows through a cursor and serializes only allowlisted fields at send time; since the ledger stores no raw prompts by default, no separate sanitized copy is persisted. Retry with backoff and idempotent IDs; telemetry never blocks the UI. Disabling export resets the cursor and drops pending batches. Transport options: bespoke REST mapping or LangSmith's documented OTLP endpoint. Bound retention and storage; surface dropped exports. Deleting local records does not itself delete previously uploaded traces: remote deletion is an explicit operation with independently reported success/failure.

## Acceptance criteria

1. A successful, failed, retried, interrupted and cached operation each produces correct local attribution without duplicate billed events.
2. Missing usage is unknown; stale external data and uncovered sources remain visible.
3. Model-unavailable and LangSmith-unavailable modes preserve focus and local records.
4. Unresolved usage is never treated as free; once concurrency is allowed, concurrent requests cannot independently spend the same reservation.
5. Urgent-task suggestions respect pinned priorities and dependencies and explain the resource they would free.
6. External-agent interruption is offered only for verified supported capabilities and never labelled pause without recovery proof.
7. Export payload tests demonstrate removal of paths, URLs, task text, secrets and private error content in metadata-only mode.
8. Local and external telemetry for one request reconcile rather than double-count; pricing revisions remain auditable.

## Sources and open questions

- [LangSmith REST tracing](https://docs.langchain.com/langsmith/trace-with-api)
- [LangSmith OpenTelemetry tracing](https://docs.langchain.com/langsmith/trace-with-opentelemetry)
- [Claude Code monitoring usage](https://code.claude.com/docs/en/monitoring-usage)
- [LangSmith cost tracking](https://docs.langchain.com/langsmith/cost-tracking)
- [LangSmith sensitive-data controls](https://docs.langchain.com/langsmith/mask-inputs-outputs)
- [Provider prompt caching example](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)

Open: external agent tools/accounts to support first; actual usage formats and retention; budget currency/timezone and reserve defaults; model provider choice; Swift exporter packaging, retry policy and deletion semantics; checkpoint/interruption support by tool. No vendor connection or capability is established by these documents.
