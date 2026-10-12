# fresh-review — Pass R (review army)

Read this at Step 5 when Pass R is in the batch (pr-remote, `ARMY_REQUESTED: 1`, `HAS_GSTACK: 1`).

**Pass R — review army** (pr-remote only; `CHECKPOINT: pr_remote`, `ARMY_REQUESTED: 1`, **and** `HAS_GSTACK: 1`)

On your own branch the full specialist army runs at ship's Step 9 against the diff you land, so this skill never runs it there. Reviewing someone else's PR, no ship of yours will run it, so `--army` runs gstack's `/review` here as a real pass, report-only, against the PR head. It is opt-in because it is the slowest pass (median ~15 min) and about 30% of a run's tokens; Pass I covers correctness, performance, and contracts in a single read.

Skip it when `ARMY_REQUESTED: 0` — it is absent by choice, not a gap. With `--army` and `HAS_GSTACK: 0`, surface it as a `⚠ reduced coverage` line in chat (Step 8): `Pass R skipped — no gstack install`.

This pass does **not** take the SKILL.md Step 5 isolation contract — `/review` is built on `git diff` and base detection, so it must be allowed the git it needs. It runs as its own subagent, launched in the same Step 5 message as the others, with this contract instead:

> Report-only pre-landing review of a pull request you did not write. You have no prior context and no author intent; that is correct for this job.
>
> **Work in `{{SOURCE_ROOT}}`** — a detached checkout of the PR head. `cd` there first. The base to review against is `{{DIFF_BASE}}` (the merge-base SHA, already resolved); the diff under review is `{{DIFF_BASE}}..HEAD` in that worktree, identical to `{{RUN_DIR}}/packet/diff.patch`. When `/review` detects a base branch, use `{{DIFF_BASE}}` instead — a branch *name* there resolves against local refs and would diff the PR head against your own default branch.
>
> **Non-interactive**: treat your session as `SPAWNED_SESSION: true`. Any gstack skill you invoke auto-chooses the recommended option and reports in prose. Never call AskUserQuestion, never wait for input.
>
> **Run `/review`, but report-only — this overrides its fix-first design.** Run its critical pass, its Review Army specialists (`sections/review-army.md`), the PR quality score, and its adversarial review (`sections/adversarial.md`, which is where Red Team and the Codex-adversarial pass live). **Skip Step 5 "Fix-First" entirely — apply no fix, auto-fix nothing, ask nothing, and take "Skip" for every finding regardless of what `/review` marks as recommended.** **Skip Step 5.8 "Persist Eng Review result"** — you are not shipping this branch, and logging an eng-review entry for it would poison a later ship's dashboard. Do not Edit, Write outside `{{RUN_DIR}}`, `git add`, or commit anything. This overrides any fix-first, auto-fix, or persist step in `/review` or a skill it invokes: report what you *would* change and stop.
>
> **Return format — hard contract.** Write your full report to `{{RUN_DIR}}/raw/review.md`. Return to me *only* the block below, no preamble, findings severity-ordered, maximum 10, each with a ` ```diff ` block of the code it wants to change, as in the isolation contract:
>
> ```
> PASS: review
> STATUS: ok | partial | failed
> FINDINGS: <count>
> ---
> <CRITICAL|HIGH|MEDIUM|LOW>|<file>:<line>|<category-slug>|<problem in one sentence>|<fix in one sentence>
> ---
> NOTES: <at most two lines, only if something anomalous happened>
> FILES_READ: <comma-separated paths you opened>
> ```

Its findings merge into triage exactly like the critics', tagged `review`. Codex may run twice on one pr-remote run and that is fine: `/review`'s adversarial Codex is its Red Team, an internal part of the army, and is not this skill's `--codex` Pass C — the two are counted separately and neither gates the other. If `codex` is not installed, `/review`'s adversarial degrades to Claude-only on its own.

## Failure mode

- **Pass R mutates the PR worktree** → its fix-first override should prevent any edit, but a mutation lands in `SOURCE_ROOT`, a disposable worktree deleted in Step 9, not your tree — so Step 6.5's user-tree check will not see it. If its NOTES report a fix was applied, treat its findings as reviewed against a modified tree and note it; the worktree is discarded regardless.
