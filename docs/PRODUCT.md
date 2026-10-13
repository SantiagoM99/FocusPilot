# Product definition

## Problem

The owner works across multiple concurrent Herdr agents, Safari/Chrome, Overleaf, and local projects. The challenge is choosing where human attention matters next and resisting habitual visits to Instagram and YouTube. Agent completion and activity in a work app do not prove task completion or progress.

## Intended outcome

The owner can start or resume a task with a clear next action, appropriate resources, and distraction rules. Important agent results enter a review queue without automatically interrupting focused work. On returning from a break, the app restores useful context.

An AI Workload view connects runs and usage to task priorities. When urgent work appears, the assistant can recommend deferring or interrupting unrelated work, explaining whether that frees spend, compute, allowance or attention. Usage visibility is partial until external tools have validated adapters.

## Principles

1. The owner defines goals, priorities, folder roots, and workspace grouping.
2. One current human action can coexist with several background agent tasks.
3. Explicit priority and deadlines outrank inferred preferences.
4. Block configured distractions immediately; ask about ambiguous activity rather than declaring procrastination.
5. Show why a recommendation was made and allow correction or dismissal.
6. Keep the focus loop useful without AI or network access.
7. Avoid continuous screenshots, keystroke collection, and full-page ingestion by default.
8. Never reward app usage as proof of meaningful output.

## First release scope

Native planning window, optional floating focus panel, menu bar controls, task deadlines and next actions, folder/context links, deterministic focus sessions, Safari and Chrome rules, Herdr status and manual pane navigation, structured local memory, and session wrap-up. Introduce lightweight coaching behind an experiment flag after this quiet loop is reliable.

Initial Herdr support is read-only plus explicit navigation. Environment creation is a separate user-triggered flow. Add explicit turn interruption only for tools that pass a capability spike; generic process termination and autonomous agent delegation are outside the first release. Introduce local model-request accounting alongside the first model calls and optional LangSmith diagnostics later.

## Release exclusions

Guaranteed anti-bypass enforcement, academic platform scraping, calendar synchronization, automatic deadline changes, cross-device sync, automatic structural reorganization, large historical vector infrastructure, continuous screen surveillance, and autonomous management of agent approvals.

## Modes

- Quiet: user-requested recommendations, existing blocking still applies.
- Coach: event-driven suggestions with suppression and cooldown.
- Strict session: deliberate friction before changing chosen rules; this does not guarantee tamper resistance.

## Success criteria

Proposed pilot: baseline week followed by a two-week Quiet/Coach comparison. Evaluate time to resume work, task maintenance burden, unwanted nudges, and actual deliverables. Also measure known AI spend by operation and useful outcomes per call, with coverage/unknowns visible. Neither screen time nor tokens saved alone is the primary success metric.

Release gates include correct deadline interpretation, recoverable workspace provisioning, consistent browser exceptions, truthful disconnected state, and no unauthorized AI action. Target values belong in the validation plan and can be revised from evidence.
