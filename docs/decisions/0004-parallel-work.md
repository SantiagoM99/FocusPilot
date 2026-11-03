# Parallel work and the second in command

Date: 2026-11-02. Status: direction agreed with the owner in conversation on 2026-11-02. The details below are proposals until each ticket's screens and behavior are signed off.

## Context

The owner rarely works on one thing at a time. On a typical day several Herdr agents run across several projects, and there are often more than four threads inside a single project. The owner also moves between hands-on tasks of their own, such as writing, coding and replying to people. The phase 1 model (one pinned Now action, one task per session) describes where the owner's attention is. It does not describe the work that moves in parallel.

Principle: **attention is single, work is parallel.** At any moment the owner looks at one thing (Now), while many threads move without them.

## Direction

### Sessions cover work, not a task list
- By default a focus session covers all projects. The owner can narrow it to one or more projects.
- Moving between the owner's own threads is never counted as a distraction. Distraction is still defined only by block rules.
- Session-only rules apply to the whole session. The resources of every task in scope are allowed.

### In flight, grouped by project
- A task is "in flight" when it has started and moves without the owner: a linked agent is working, or the owner marked it as waiting on someone or something.
- In flight is grouped by project and collapsed by default: "NLP report · 5 threads · 2 need you". Expanding a project shows each thread with its state: working, needs you, finished, waiting.
- Thread count has no limit.

### Attention queue
- A separate list, at the top, holds only the threads that need the owner now: an agent asking for approval, an agent that finished, a check the owner scheduled.
- It is ordered by priority and deadline, then by how long the item has waited.
- An item that waits on the owner too long gets a quiet alert (proposed default: 30 minutes). Waiting time matters more than thread count.

### Switch with one click and a note
- "Switch" works from the attention queue, from In flight, or from the floating panel. It asks one optional line, "Where did you leave off?", and saves it as the return cue of the current task. It then makes the target task Now and opens its agent or resources. That opening is the explicit owner click required by the S4 rules.
- When the owner returns to a task, its return cue is shown first.
- FocusPilot never changes Now or focus by itself.

### Floating panel shows where the owner is needed
- During a session the floating panel shows the top one or two attention-queue items, each with a Switch button. Example: "ablation-agent finished · NLP report · Switch".
- The panel never switches on its own. It makes no sound and has no pulsing or flashing.

### End of session
- The wrap-up lists every task touched in the session, with one optional line each. Rows are stored in the existing wrap-up history.

### Metrics
- The weekly summary adds three measures:
  - switches per hour;
  - time to get back into each thread;
  - how long agents waited for the owner after asking for something, which shows whether the owner is the bottleneck.

## Second in command (phase 2)

A FocusPilot assistant that takes repetitive coordination work off the owner. Phase 1 excludes autonomous delegation, and it touches agents, AI cost and permissions, so it is phase 2.

- **Level 1: propose, the owner approves.**
  - It reads finished agent results and summarizes them for the attention queue.
  - It drafts the next step for an agent, for example "Tests pass. Ask it to open the PR?".
  - It acts only after the owner clicks Accept.
- **Level 2: standing rules the owner writes.**
  - For narrow, repetitive cases the owner grants permission in advance. Example: "When my agent finishes and its tests pass, tell it to open the PR."
  - It acts alone only inside those rules, logs every action, and each rule can be turned off.
  - This is a deliberate, owner-written exception to the AGENTS.md default of no autonomous prompts or approvals.
- **Communication is a hard requirement.**
  - It writes plain, natural English that a person understands completely on the first read.
  - No filler, hype or AI-style phrasing.
  - Every message states what happened, what it means and what the owner should do.
  - Summaries are judged on this before anything else.
- **First use cases (owner, 2026-11-02):** PR reviews in the Bowling project; diagnosing GitHub Actions pipeline failures; investigating data and web-app errors that the team reports in WhatsApp, using the parquet data in the Observatory Data Flow project. WhatsApp cannot be read by a program, so the owner shares or pastes each report.
- **Architecture direction:** the assistant runs as its own Herdr agent with runbooks for these jobs. FocusPilot is the cockpit (attention queue and one-click approval). Data access is read-only.

## Tickets

- T19: sessions that cover projects instead of one task.
- T20: In flight by project, attention queue, Switch with a note, and attention items in the floating panel.
- T21: parallel-work metrics.
- Phase 2 epic: second in command (level 1, then level 2).
