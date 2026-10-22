# fresh-review — pr-remote

Read this at Step 1.5 when `PR_REF` is set. Keep it for the rest of the run.

## Step 1.5: Resolve the PR (pr-remote only)

Skip entirely unless `PR_REF` is set.

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-pr-resolve.sh" "$RUN_DIR"
```

Turns the ref into a reviewable local diff plus a tree reviewers can open files from, and overwrites `REVIEW_SCOPE`, `DIFF_BASE`, `DIFF_CMD`, and `SOURCE_ROOT` in `state.env`. It also sets `CHECKPOINT=pr_remote`, which is what makes Steps 3, 6.5, 8.6, and 9 take their pr-remote branches without being told twice.

**Why a detached worktree and not just `gh pr diff`.** Reviewers are told to open a source file when the patch alone cannot settle whether something is a defect — `/cso` in particular is nearly blind without the surrounding code. With only a patch, those reads would hit your checkout, which is a *different commit*, and the reviewer would confidently judge the PR against the wrong file contents. So the PR head is materialized once and `SOURCE_ROOT` points every pass at it. The cost is one checkout; the alternative is findings that describe a file nobody is proposing to merge.

`git worktree` places it under `.fresh-review/` when that path is gitignored and in `$TMPDIR` otherwise — never under the git dir, and never anywhere git would report it as untracked dirt inside the diff under review.

On `PR: unresolved`, **stop and say why.** There is no safe default: falling back to the local branch would review the wrong change under the PR's number. `REASON` is one of:

- `gh_missing` — install/authenticate `gh`, or drop the ref and run `--mode pr` on a local branch instead.
- `bad_pr_ref` — the ref was neither a bare number nor a `github.com/…/pull/N` URL.
- `foreign_repo` — the URL is a PR in a different repo than this checkout's `origin`. There is no tree here to build a worktree from. Clone that repo and run there.
- `gh_pr_view_failed` / `gh_pr_view_incomplete` — read `raw/pr-view.err`; usually auth or a wrong number.
- `pr_fetch_failed` — `origin` does not serve `pull/N/head`. Non-GitHub remotes do not.
- `no_merge_base` — the PR's base branch and head share no history.
- `worktree_failed` — read `raw/pr-worktree.err`.
- `since_pr_not_below` — `--since-pr` named a PR that is not below the `--pr` PR in its stack. The walk down the base branches reached trunk (or 30 links) without meeting it.

**With `--since-pr`** (a stack unit), the script walks the stack down from the `--pr` PR to the `--since-pr` PR and records `STACK_PRS` (bottom to top) and `UNIT_BASE` (the bottom PR's base branch). `DIFF_BASE` is the merge-base of `UNIT_BASE` and the top PR's head, so the packet holds the whole unit. Everything else — the worktree, `PR_HEAD`, the verdict vocabulary — is the top PR's.

Two resolved outputs to state out loud:

- `HEAD_DRIFT: yes` — the PR was pushed to between the `gh` call and the fetch. Not an error, but the report must name the commit actually reviewed, which is `PR_HEAD`, not what `gh` reported.
- `PR_STATE` — `MERGED` and `CLOSED` are reviewable (narrating a merged PR is a legitimate use). Just say which, so nobody acts on a `REQUEST-CHANGES` for a PR that landed last week.

**The PR title is fetched and deliberately withheld from every isolated pass.** It is in `$RUN_DIR/pr.json`, and it goes in the Step 8 header for the human to read — but never into the packet or an isolated subagent prompt. The title is the author's claim about the change; Pass U's value is explaining the change from the code alone, and a divergence between the two is a finding rather than an input. The body, the human discussion, and any static-analysis bot findings are fetched too — but by **Step 4.7** (`fr-pr-context.sh`) into `$RUN_DIR/pr-context/`, which is producer-only: it feeds triage and the static-analysis verification (Pass W), and is on every isolated pass's forbidden-reads list. The isolated passes never see it; that separation is what the "Keep passes blind" design turns on.

## At Step 10: record the review

**In pr-remote, record the review first,** so a later re-review can start from it. Do this only when the implementation review ran (`ARCH_GATE` is not `pending` or `rejected`). Write `$RUN_DIR/blockers.json`: a JSON array of this run's bucket-1 findings, `[]` when there are none. Each item is `{"severity","file","line","category","problem","fix","sources"}`, and the first six keys are required. **Copy `severity`, `category`, `problem`, and `fix` word for word from the pass line that raised the finding.** Pass F reads this text in the next re-review. You chose which findings are blockers with the PR discussion in hand, and a rewrite in your words would carry that discussion into an isolated pass. For a merged finding, take the line of the first source. On a re-review it holds the still-open earlier blockers (Pass F's lines) and the new ones, so the next re-review checks both. The third argument is the run's coverage: `reduced` when the Step 8 `⚠ reduced coverage` line printed, otherwise `full`. A reduced review is recorded, and the next `--delta` asks whether to review only the changes or the whole PR. The script also records the architecture gate: `approved` when the user approved the architecture in this run, at invocation, or at the last review (a `carried` gate, or a low or medium delta after an approved one). With an approved gate, it keeps the architecture report next to the record, for the next re-review's Pass U: on a gate the user approved in this run, this run's `raw/architecture.md` (plus, on a delta, the earlier ones); on a carried gate, or a delta whose tier was low, medium, or unknown, the earlier ones unchanged. Then:

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-review-record.sh" "$RUN_DIR" "$VERDICT" "<full|reduced>"
```

`RECORD: written` → done. `RECORD: failed` → say `This review was not recorded (<REASON>); a later re-review of PR #<n> will run as a full review.` and continue. `REASON` is `bad_blockers` (fix `blockers.json` and run it again), `bad_verdict`, `bad_coverage`, `not_pr_remote`, `ref_update_failed`, or `record_write_failed` (the refs moved but the JSON did not; the next re-review sees `record_mismatch` and runs in full).

## Failure modes

- **`PR: unresolved`** → stop, print `REASON` and its remedy from Step 1.5. Never fall back to reviewing the local branch: it would answer a question about PR #42 with a review of something else entirely.
- **PR head moves mid-review** (`HEAD_DRIFT: yes`) → not an error. Everything was reviewed at `PR_HEAD`; say so in the header and move on. Do not re-fetch — that would mix two commits' findings in one report.
- **PR worktree survives the run** (`WORKTREE: failed`) → tell the user the path and that `git worktree remove --force <path>` clears it. Do not leave it undisclosed; it is a full checkout's worth of disk.
- **The review record is not written** (`RECORD: failed`) → continue, and say that a later re-review will run as a full review.
