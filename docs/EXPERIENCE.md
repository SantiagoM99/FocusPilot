# Native experience and flows

## Visual direction

Use the macOS system font, SF Symbols, native sidebar behavior, semantic system colors, understated accent, generous spacing, and restrained animation. Support light/dark, increased contrast, reduced transparency/motion, keyboard access, and VoiceOver. Apply materials around controls; task text needs a stable readable surface.

No productivity scores, shame copy, constant pulsing, or automatic pane focus. The assistant is represented by a small status indicator and one useful sentence; expand into conversation when needed.

## Planning window

Sidebar: Today, Projects, Review queue, AI Workload, Memory, Settings. Center: pinned Now action and manually ordered Next/Later tasks. Detail pane: deadline, rationale, resources, workspace, and next action. Agent status appears on its linked task. Relative deadlines also show an exact date/time on inspection.

```text
┌──────────────┬──────────────────────────┬─────────────────────────┐
│ Today        │ NOW                      │ NLP report              │
│ Projects     │ Explain baseline results │ Due Fri 23:59 · Bogotá   │
│ Review queue │ [Start working]          │ Next action / resources │
│ AI Workload  │                          │                         │
│ Memory       │ NEXT                     │ Herdr: results ready    │
│ Settings     │ PhD shortlist            │ [Review] [Open context] │
└──────────────┴──────────────────────────┴─────────────────────────┘
```

## Focus panel and menu bar

Optional movable/collapsible AppKit panel. Next action, elapsed/remaining time, protection health, and queued agent count. Pause and Complete actions. Never obscures active typing. Menu bar popover exposes equivalent controls without the floating panel.

```text
┌──────────────────────────────────────┐
│ Focusing                      24:08 │
│ Explain baseline results            │
│ Overleaf · NLP report               │
│ Safari + Chrome protected           │
│ 1 agent result queued               │
│ [Pause]                  [Complete] │
└──────────────────────────────────────┘
```

## AI Workload and usage detail

Native table grouped by task, with an unattributed section. Columns: task urgency/deadline, agent state, tokens or allowance, estimated spend, freshness, and available actions. Global summary shows period/timezone, known consumption, budget/reservations, coverage and unresolved usage. Missing telemetry displays Unknown, never $0.

Selecting a run opens details with source, provider/model, measurement quality, checkpoint if available, and usage breakdown. A recommendation shows the exact resource it would free and whether the run supports interruption. A budget warning never automatically interrupts an external agent or silently changes the current task.

Controls are labelled Defer next job, Interrupt turn, or Open agent. Do not display Pause unless resumption is supported and tested. Generic Stop process is outside the first release. The interruption preview names the agent/task, last state, potential loss, and supported mechanism. Revalidate before execution; show the reconciled outcome afterward.

AI Activity details expose supervisor requests, cache hits, retries and useful/dismissed suggestions. LangSmith settings are separate: export off by default, metadata-only option, distinct content opt-in, connection health, and remote deletion status. A full tracing console need not dominate the everyday task view.

See [workload visual study](AI_WORKLOAD_BOARD.svg). Values are illustrative, not collected usage.

## Blocked page

Current action, break time, Return to task, and deliberate timed exception request, scoped to this exact page (e.g. one lecture video) or the whole site. Outside a focus session, a site blocked by an always-on or scheduled rule shows which rule applies (and when a schedule ends) instead of a current action. No arbitrary commands from page content. Global policy reports the remaining exception in both browsers. If redirect behavior is unsupported for a case, use truthful browser feedback and app notification rather than pretending navigation succeeded.

## Coach behavior

Separate hard-blocked sites, explicitly allowed context, and ambiguous activity. Grace period only applies to ambiguous activity. Initial proposal: 60 seconds before check-in, at most one unsolicited check-in per 15 minutes, and suppress repeated nudges for a user-marked relevant context during that session. These are pilot hypotheses, not fixed requirements.

Unknown apps and sites (owner decision, 2026-10-13): anything not in the owner's allowed or blocked lists counts as ambiguous. A deterministic rule triggers the check-in, not model confidence; the model may only pre-fill a suggested purpose. After the grace period, ask once:

```text
Zotero opened during "Explain baseline results". What's it for?
[For this task] [Always fine] [Distraction] [Ask later]
```

- For this task: allowed whenever this task or project is active.
- Always fine: added to the global allowed list.
- Distraction: proposed for the blocked list; the owner confirms before it is blocked.
- Ask later: no further question this session.

A seeded allowed list (Finder, Terminal, System Settings, Overleaf, Herdr and similar) never triggers questions. Ask at most once per app per task, respect the unsolicited check-in limit, never interrupt active typing, and treat browser sites the same way. Answers are editable in Settings.

Check-in responses: Relevant, I'm stuck, Change task, Take a break, Snooze. Agent results are queued unless they materially unblock the chosen human action. Approval-required status is shown without answering it.

## Flows

1. Capture: type task and deadline → inspect interpretation → save → link context when useful.
2. Existing work: choose task → revalidate resources/Herdr target → preview context → Start → focus session.
3. New academic/application work: choose root/category → prepare setup preview → Create → attach folder/workspace/resources → Start.
4. Drift: block forbidden site immediately or check ambiguous activity after grace → user response updates session context → resume.
5. Agent result: refresh state → link output to task → queue review → owner explicitly opens pane → record next action.
6. Finish/break: brief outcome and return cue → save → end or pause policy according to chosen rules.
7. Recovery: detect stale integration after restart/wake → reconcile session/policy → show actual protection state.
8. Urgent task: pin urgent action → inspect AI Workload recommendation → defer managed queued work or preview supported turn interruption → revalidate target → execute explicit action → reconcile state and preserve return cue.
9. Budget limit: account/reserve usage → reject optional calls beyond admission limit → keep deterministic focus behavior → offer explicit budget override without claiming control over external billing.
