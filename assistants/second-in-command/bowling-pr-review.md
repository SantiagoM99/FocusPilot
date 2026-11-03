# Runbook: Bowling PR review

Job: review **marilynjov's** pull requests in `marilynjov/Bowling`. Those are the PRs the owner (SantiagoM99) must review as the other developer. The owner's own PRs belong to marilynjov to review, so leave them alone.

Work in `~/Projects/Personal/Bowling`. Read its `AGENTS.md` and the specs it points to. They are the standard every review is measured against: the package contract, the CloudKit schema rules, testing in packages, and one branch per issue.

## Steps

1. **Find work.** Run `gh pr list --repo marilynjov/Bowling --author marilynjov --state open`, and keep the PRs that have no review from SantiagoM99 since their last push.
   Done when you have that list. If it's empty, stop: there's nothing to report.

2. **Review each PR.** Use a fresh worktree for each one and never touch the owner's working copies. Check:
   - **The issue:** read the linked issue and check that the PR does what it asks. Compare the code change against the issue, not just against the PR description.
   - **The contract:** look at every change to BowlingCore value types, repository methods, `StatsReport`, `BallReport` or stats card IDs. A contract change needs both developers' agreement, so flag it.
   - **The schema:** check any SwiftData model change against the CloudKit rules in the roadmap.
   - **Correctness:** look for real bugs. For each one, name a concrete input and the wrong result it produces.
   - **Tests and CI:** check the PR's checks with `gh pr checks`. Where the change is in packages, run `swift test` for the affected package.

   Done when every changed file has been read and every check above has an answer.

3. **Report.** Send one FocusPilot report per PR, following the Writing rules in `ROLE.md`.
   - **First line:** either "Ready to approve" or the count of real problems.
   - **Body:**
     - each real problem, with file:line and the breaking input;
     - a "Minor" list of at most three items;
     - "Not checked:" with anything you couldn't verify.
   - **Proposal:** the exact review text to post.
     - If there are no real problems, the proposal is an approval with that text.
     - Otherwise it is a comment review with that text.

   Done when every PR on your list has a report.

## What an Accept unlocks

When the owner's Accept message arrives for a PR, post exactly the proposed review with `gh pr review`. Use `--approve` only when the proposal said approve, and `--comment` otherwise. Then confirm in one line that it was posted, and stop.

An Accept authorizes only that review on that PR. Merging, pushing and requesting changes stay with the owner.
