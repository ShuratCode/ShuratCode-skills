# fresh-review — re-review (`--delta`)

Read this at Step 1.6 when `DELTA` is not `off`. Keep it for the rest of the run.

## Re-review: only the delta

**pr-remote and stack units only.** After the first review, the author pushes fixes, and the user asks for a re-review. `--delta` then reviews only what changed since the last review of that PR, not the whole PR again.

1. **Every finished pr-remote review is recorded** (Step 10). `fr-review-record.sh` writes the PR head it reviewed, the merge-base, the verdict, the open blockers, the risk class, and whether the run had full coverage to `$LOG_DIR/reviews/<key>.json`. It pins both commits with refs under `refs/fresh-review/reviewed/<key>/`, updated in one transaction, so a force-push cannot lose them. `fr-delta.sh` checks that the refs and the record agree before it trusts either. The key is `pr-<n>`, or `pr-<top>-since-<bottom>` for a combined stack unit.
2. **The delta is the author's changes only** (Step 1.6). `fr-delta.sh` replays the PR as it was at the last review onto the PR's current base (`git merge-tree`), and diffs that against the new head. So a rebase or a merge of `main` does not show `main`'s changes as if the author made them. It builds two local commits for this and moves the PR worktree onto the second one. Its files are the PR head's files, so reviewers read the right code, and Codex and `/review` see the delta through `DIFF_BASE..HEAD`.
3. **The earlier blockers are checked** (Pass F). One isolated pass reads the last review's blockers and the current code, and reports the ones that are still open. An open one stays a blocker (Step 7).

Everything else runs as usual on the delta: the risk tier and brief, the implementation passes, Pass R (with `--army`), and Pass W. The tier is the delta's tier. The mechanical risk has one floor: when the last review was `RISK: high`, the re-review is high too, so Codex and `/cso --comprehensive` still run on a small fix to a high-risk PR.

When there is no record — the first review ran on an older copy of the plugin, which had no record step — it uses the newest run-log entry of that PR instead, and that run's findings for the earlier blockers.

When a delta is not possible, the skill says why and does the safe thing. The user asked for a delta, so it never turns into a full review in silence. With no earlier review, it asks whether to run a full review. When the earlier review lost a lens, or its blockers are unknown, it asks: only the changes (with the gap named), or the whole PR. With a record it cannot trust, or an old PR that no longer applies to the new base, it runs a full review. With no new changes since the last review, it stops. See Step 1.6.

When the user approved the architecture at the last review, a high-tier delta that adds no new parts does not stop again (`carried`).

## Step 1.6: act on the delta result

It reads the record of the last finished review of this PR (or stack unit), keyed by `REVIEW_KEY`. When there is no record, it falls back to the run index: the newest `runs.jsonl` entry of a finished pr-remote review of this PR alone (not a delta run, not a stopped gate, not a combined stack unit) whose PR head and merge-base are still in the repo. Its blockers come from that run's `findings.tsv` (bucket 1; a header with no rows means none) when the run directory was not pruned. Run directories are looked up only in this run's report dir and in each worktree's git dir or own report dir — never inside a PR worktree, whose files the PR author controls — and a symlinked run directory or file is ignored. Its coverage is `full` only when every lens pass the run should have had (lattice, cso, the review army, Codex when requested, and Pass F and Pass W when they ran) is present and `ok`, and the architecture gate did not fail. A record written before `arch_gate` existed takes its gate and decisions from its own run-index entry and run directory. A run that ran from an older copy of the plugin, with no record step, is found this way. `DELTA_SOURCE` says which one it used: `record`, `runs_index`, or `none`. A combined stack unit has no index fallback: the index does not name the bottom PR.

When a prior review exists, it also reports `PRIOR_COVERAGE` (`full` or `reduced`) and `PRIOR_ARCH_GATE` (`approved` when the user approved the architecture at that review, or at a review it carried that from). With `PRIOR_ARCH_GATE: approved`, it copies that review's architecture report to `$RUN_DIR/delta/prior-architecture.md` for Pass U, when it is on disk.

`DELTA` comes back as one of:

- `applied` — the delta is ready. The script has overwritten `DIFF_BASE` and `DIFF_CMD` in `state.env` and moved the PR worktree to `DELTA_HEAD` (same files as `PR_HEAD`). It wrote the earlier blockers to `$RUN_DIR/delta/prior-blockers.md` for Pass F. Say: `Re-review: only the changes since the last review at <PRIOR_HEAD short sha> (<PRIOR_VERDICT>, <PRIOR_BLOCKERS> blockers).` When `DELTA_KIND` is `rebased`, add: `The PR was rebased or merged with its base since then; the base's own changes are left out.` When `DELTA_SOURCE: runs_index`, add: `The last review has no record (it ran on an older plugin copy); using its run-log entry.` When the user accepted a gap after `ask`, that gap goes in the Step 8 `⚠ reduced coverage` line: `the last review lost <lens>; only the changes since then were reviewed` (`DELTA_PRIOR_COVERAGE: reduced`), or `earlier blockers not checked — the last review's findings were pruned` (`DELTA_PRIOR_BLOCKERS: unknown`).
- `ask` — the user asked for a delta, and the choice between a delta and a full review is theirs. The script has **not** moved the worktree. Never run the full review without an answer: the user said `--delta`, and a silent full review costs them the whole run again. `DELTA_REASON` is one of:
  - `no_prior_review` — no record and no usable run-index entry. A delta is not possible. Call **AskUserQuestion** once — question: `No earlier review of PR #<n> was found here. Run a full review?`, header `Re-review`, options `Full review` and `Stop here`.
  - `prior_reduced_coverage` — the last review lost a lens (name it from that run's pass line or log when you can, e.g. `cso partial`). Its code was never fully reviewed by that lens.
  - `prior_blockers_unknown` — the prior review came from the run index and its run directory was pruned, so its blockers cannot be checked.

  For the last two, call **AskUserQuestion** once — question: `The last review of PR #<n> (<PRIOR_VERDICT>) <the gap in a few words>. Review only the changes since then, or the whole PR?`, header `Re-review`, options `Only the changes (Recommended)` — `the gap is named in the coverage line` — and `Whole PR`. Then run the script again with the answer:

  ```bash
  . "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-delta.sh" "$RUN_DIR" --choice delta   # or --choice full
  ```

  It returns `applied` (or `none`), or `full` with the same reason. Handle that output as below. On `Stop here`, run Step 9 and stop, with no log entry. When no one can answer (AskUserQuestion is unavailable or fails), do not pick for the user: run Step 9, stop, and say how to continue — re-run without `--delta` for a full review, or answer the question.
- `full` — a delta was asked for but is not possible, or the user chose the whole PR. Say why in one line and run the full review. `DELTA_REASON` is `no_prior_review` or `prior_reduced_coverage` or `prior_blockers_unknown` (the user chose it after `ask`), `record_invalid` (the record is not valid JSON or has malformed blockers), `record_mismatch` (the refs and the record describe different reviews — a record write was interrupted), `prior_head_missing` (the record's commits, or the run index entry's, are gone), `rebased_with_blockers` (the base moved and the PR's own changes are the same, but earlier blockers are open — the new base may have fixed them, so the whole PR is checked again), `replay_conflict` (the old PR no longer applies cleanly to the new base, so the author's changes cannot be separated from the base's), `replay_failed` (git could not replay it — `raw/delta-replay.err`), or `worktree_failed` (`raw/delta-checkout.err`).
- `none` — there is nothing new to review. `DELTA_REASON` is `no_new_commits` (the same head on the same base as last time), `no_net_change` (new commits on the same base that cancel out, such as a push and its revert), or `rebase_only` (the PR was rebased or retargeted, its own changes are the same, and no earlier blocker is open). Say `Nothing to re-review on PR #<n>: <reason>. Last review: <PRIOR_VERDICT>, <PRIOR_BLOCKERS> blockers.` When `PRIOR_COVERAGE: reduced`, add: `That review had reduced coverage; re-run without --delta for a full review.` Then run Step 9 to remove the PR worktree, and stop. No log entry.

The record is written only at the end of a finished review (Step 10), so a run that stopped for approval, or whose design the user rejected, does not count as the last review.

## Pass F — fix check

**Pass F — fix check** (re-review only; `DELTA: applied` and `DELTA_PRIOR_BLOCKERS` above 0. With `DELTA_PRIOR_BLOCKERS: unknown` it does not run: there is nothing to check, and the gap is named in the coverage line.)

A re-review looks at the delta, so a blocker the author did not touch would never come up again. Pass F closes that gap: it checks each blocker from the last review against the current code. It takes the isolation contract verbatim, with one exception to its forbidden reads, then this task, which replaces the contract's return-format block:

> Your job is to check whether the blockers from the last review of this PR are fixed. Read `{{RUN_DIR}}/delta/prior-blockers.md` — the only file under `{{RUN_DIR}}/delta/` you may read. It lists each earlier blocker with the file, line, problem, and the fix that was asked for. Its line numbers are from the old code.
>
> For each blocker, open the file from `{{SOURCE_ROOT}}` and find the code the blocker is about. It may have moved. Decide:
>
> - **FIXED** — the problem is gone from the current code. It does not matter whether the fix is the one asked for.
> - **OPEN** — the problem is still there, or only part of it was fixed, or you cannot find the code and cannot show it was removed.
>
> Use `diff.patch` to see what changed, but judge by the current source. Do not look for new problems — other passes do that. Report only the OPEN blockers, at their earlier severity, with the current `file:line`.
>
> Write your reasoning for every blocker to `{{RUN_DIR}}/raw/fix-check.md`. Return *only* this block:
>
> ```
> PASS: fix-check
> STATUS: ok | partial | failed
> TOTAL: <n>  FIXED: <n>  OPEN: <n>
> ---
> <CRITICAL|HIGH|MEDIUM|LOW>|<file>:<line>|prior-blocker-open|<B<n>: the earlier problem, and what is still wrong>|<the fix still needed>
> ---
> NOTES: <at most two lines, only if something anomalous happened>
> FILES_READ: <comma-separated paths you opened>
> ```

Pass F is isolated like the critics. The earlier blockers are findings from an earlier review, not author intent, so it may read them. It may not read `pr-context/`. Its OPEN lines go to triage under the prior-blocker floor (Step 7).

## Failure modes

- **Re-review with no record, but a run-log entry** (`DELTA_SOURCE: runs_index`) → not an error. The first review ran on an older copy of the plugin — often a desktop session snapshot that lagged the install — so it logged the run but wrote no record. The delta uses the run-log entry. This run writes the record for the next re-review.
- **Re-review with no earlier review at all** (`DELTA: ask`, `no_prior_review`) → not an error. The first review ran in another clone, or did not finish. Ask whether to run a full review (Step 1.6). Never start it without the answer; it becomes the record for the next re-review.
- **The last review's run directory was pruned** (`DELTA: ask`, `prior_blockers_unknown`) → ask: only the changes, with `earlier blockers not checked` in the coverage line, or the whole PR.
- **The old PR no longer applies to the new base** (`replay_conflict`) → the author's changes cannot be separated from the base's. Say so and run the full review. Do not hand-build a delta.
- **Nothing new since the last review** (`DELTA: none`) → say so with the last verdict, remove the PR worktree (Step 9), and stop.
- **A record the delta cannot trust** (`record_invalid`, `record_mismatch`) → run the full review. It writes a fresh record, which repairs the state for the next re-review.
- **The last review lost a lens** (`DELTA: ask`, `prior_reduced_coverage`) → ask: only the changes, with the lost lens named in the coverage line, or the whole PR, so the code the reduced run saw gets every lens once. Never pick for the user. With no answer possible, stop and say how to continue.
- **Pass F fails** → continue. Name it in the reduced-coverage line (`earlier blockers not checked`), keep the `fix-check` pass with `"status":"failed"`, and carry the earlier blockers into `blockers.json` unchanged, so the next re-review checks them again.

## Example

**"re-review PR 42"** after the author pushed two fix commits → `--pr 42 --delta`. Step 1.6 builds the delta. Pass U sets the delta's tier: the fixes touch no parts, so `low`, and the run does not stop. Pass F checks the two earlier blockers: one fixed, one still open. A new readability finding in unchanged code goes to SHOULD FIX, marked `pre-existing`, and does not block.
