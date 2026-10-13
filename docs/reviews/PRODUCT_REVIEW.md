# Independent product critique

Reviewer: product_detractor. Date: 2026-10-13. Adversarial review requested by the owner. These are hypotheses and proposed targets, not results from a user study.

## Findings and dispositions

| Criticism | Recommended change | Disposition |
|---|---|---|
| Task management may add more overhead than it saves | Minimal capture, progressively attach context, remember links | Accepted: basic capture must work without extensive metadata |
| Intelligent interruptions still fragment work | Queue Herdr results, rate-limit coaching, support quiet periods | Accepted: coach experiment is optional; current action stays pinned |
| Urgency can displace important long-term goals | Separate ready-for-review from should-do-now; explain recommendations | Accepted: completion is not a priority override |
| Apps/tabs cannot establish intention | Hard blocks for explicit rules; ask about ambiguity; timed exceptions | Accepted: never infer task completion from activity |
| Strict supervision can become adversarial | Visible pause/break/change-task controls; no shame or hidden escalation | Accepted: AI approval never required to exit Coach mode |
| Workspace automation creates clutter/launch overload | Multiple tasks may share contexts; minimal launch set separate from resources | Accepted: starting existing work creates no new workspace |
| MVP bundles several products | Deliver end-to-end quiet loop before expanding supervisor | Accepted: proactive coaching is tested independently |

## Potentially fatal assumptions

1. Detailed manual task upkeep is sustainable. Test sparse data first; simplify if daily upkeep consumes the benefit.
2. Activity observation can reliably infer progress. It cannot support autonomous completion or moral judgments.
3. Active supervision improves on next-action display plus blocking. This must be measured; do not assume it.

Manageable risks: stale status, false suggestions, notification fatigue, and disconnects, if visible and reversible. Anti-bypass enforcement is a separate commitment.

## Proposed pilot criteria

- Simple task capture <=30 seconds; resume existing task <=2 interactions.
- Planning/maintenance <5 minutes/day after setup.
- At most one unsolicited coaching nudge per 15 minutes initially; reconsider triggers if >20% are judged irrelevant.
- Zero automatic changes to pinned task; every recommendation has a rationale.
- Relevant-context correction suppresses repetition for the session.
- Coach-mode break or task switch <=2 interactions, without model approval.
- Existing-task launch creates zero folders/workspaces and opens only configured launch resources.
- Core loop functions with AI disconnected.

Compare Quiet and Coach on comparable real academic/project sessions over a two-week pilot. Measure completed intended actions, resumption ease, maintenance burden, unwanted nudges, and accepted suggestions. Keep proactive supervision only where it improves the experience.

## Product refinement

Position FocusPilot as a reliable task launcher and focus controller with selective supervision. Its defensible promise is helping the owner return to an actionable step without reconstructing the project, not proving whether the owner is focused.
