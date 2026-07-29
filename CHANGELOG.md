# Changelog

## 0.4.0 — 2026-07-29

### New plugin: `pull-all` 0.1.0

`/pull-all <path>` walks a directory tree, finds every git repo under it, and brings each
one's main branch up to date with origin — in parallel, with one summary block instead of
per-repo git noise. `plugins/everything` 0.1.0 → 0.2.0 to pick it up.

The work is in `scripts/pull-all.sh`; the skill is its man page. Semantics that fell out of
testing against a fixture tree covering clean / dirty / detached / diverged / `master`-default
/ no-remote / submodule / no-local-main repos:

- **Never switches branches.** A repo checked out on `feature/x` gets its main advanced via
  `git fetch origin main:main`, which moves the ref without touching the worktree. Verified:
  the branch stays `feature/x` and the working file stays at its pre-update content while
  `main` lands exactly on `origin/main`.
- **Never merges non-fast-forward.** `merge --ff-only` for the checked-out case, a plain ref
  fetch otherwise. Ahead-*and*-behind is reported `DIVERGED` and left alone.
- **Never touches a dirty tree** (tracked modifications ⇒ `SKIPPED`; untracked files are
  ignored, since they don't block a fast-forward).
- **`git pull` is never invoked**, so a configured `pull.rebase` can't change behavior.
- Statuses sort worst-first — `FAILED`, `DIVERGED`, `SKIPPED`, then `UPDATED` / `CREATED` /
  `CURRENT` — so the lines needing a human are at the top of what the agent reads.

Two defaults exist because the first real scan of `~` got them wrong:

- **Dot-directories are pruned.** Without that, a `~` scan finds `~/.nvm` and `~/.oh-my-zsh`
  and offers to update them. `~/.nvm` sits at a detached HEAD, so it would have grown a local
  `master` branch it never had. `--hidden` opts back in.
- **A missing target branch is `SKIPPED`, not created.** Creating branches in a repo that
  deliberately has none is the surprising choice; the fetch already refreshed `origin/main`,
  so there is nothing lost. `--create` opts in.

The find expression is `\( -name '.[^.]*' ! -name .git \) -prune -o -name .git -print`. The
`! -name .git` is load-bearing — `.git` is itself a dot-name, so pruning dot-dirs without the
exclusion prunes every repo before `-print` sees it and the script silently reports zero repos.

Written for bash 3.2 (macOS `/bin/bash`): no associative arrays, no `wait -n`, no `mapfile`.
The `-j` throttle polls `jobs -rp`, and the per-repo network timeout is a hand-rolled
background-and-poll helper rather than `timeout(1)`, which macOS doesn't ship. `GIT_TERMINAL_PROMPT=0`
plus `ssh -o BatchMode=yes` mean an auth-requiring remote fails fast instead of hanging on a prompt.

#### Bare repos with linked worktrees

Running against a real 18-repo work tree found two bugs the synthetic fixtures missed, both
triggered by one repo: `core.bare = true`, files still on disk, real checkouts living in
linked worktrees (the Cursor / `.claude/worktrees` pattern).

- **A bare repo still answers `symbolic-ref HEAD` with a branch name**, so the target looked
  checked out and the run took the `merge --ff-only` path, dying with `fatal: this operation
  must be run in a work tree`. Bare is now detected with `git rev-parse --is-bare-repository`
  and routed to the ref-fetch path, which is what a bare repo wants anyway.
- **`git status` exits 128 in a bare repo, and the dirty gate read it as clean.** Only stdout
  was captured, so an errored status was indistinguishable from no modifications — the repo
  passed the safety check and then failed at the merge. A crash was the *lucky* outcome here;
  the same fail-open would have mattered more in a repo where the merge could have succeeded.
  The check now tests the exit status and reports `cannot read status`.

Handled while in there: if the target branch is checked out in a *linked* worktree, git
refuses to fetch into it, so the ref-fetch path is unavailable. The fast-forward runs inside
the worktree that holds the branch instead — the only place it has a working tree to move —
and reports `UPDATED  main +3 in worktree ~/.cursor/worktrees/foo/abcd`. That worktree gets
the same dirty guard as any other checkout, so a holder with tracked modifications is
`SKIPPED` with its edits intact.

Note that `git worktree list` includes the *primary* worktree, so on an ordinary repo sitting
on main the reported holder is the repo directory itself. The worktree lookup runs only after
the `cur == target` case has returned, so normal repos never reach it and nothing is handled
twice; only genuinely linked holders take that path.

Both shapes are now permanent fixtures. Verified on the work tree: 9 repos fast-forwarded to
land exactly on `origin/*`, a repo on `docs/add-agents-md` kept its branch and worktree, the
bare repo's three Cursor worktrees were untouched, and 3 dirty repos stayed dirty and
un-advanced.

## 0.3.1 — 2026-07-27

### `fresh-review` 0.2.0 → 0.2.1

**The reviewer-mutation guard was dead on clean-tree runs, and it failed silently.** Step 3 is
skipped wholesale when `DIRTY=0`, which left `CHECKPOINT` and `CHECKPOINT_SHA` unset. An unset
`CHECKPOINT` is not `committed`, so Step 6.5 took its no-checkpoint branch and diffed against a
`pre-fanout.status` that was never written. `diff` sends that error to *stderr* and `|| true`
swallows the exit code, so `LEAK` captured empty stdout and the check reported **no leak**
regardless of what a reviewer wrote to the tree. A crash would have been the better failure —
this looked like a passing safety check.

The dead path is `DIRTY=0` + `AHEAD>0`, which Step 1 itself calls "the normal shape of an open
PR whose work is fully committed and pushed" — so the guard was inert on one of the skill's most
common invocations. Reported by Copilot on `vi-activate` PR #262 (filed as low-confidence; it was
correct).

Fixed by treating the skipped case like the clean-tree case, which is the stronger of the two
available checks: when `DIRTY=0` the tree genuinely was clean at fan-out, so *any* dirt is a
leak, where a baseline snapshot would only have caught deltas. Step 3 now sets
`CHECKPOINT=skipped` explicitly, Step 6.5 matches `committed|skipped` with `case` and documents
that neither `skipped` nor an unset value may fall through, and Step 9's index restore is gated
on `!= skipped` so the code matches its own stated rule rather than relying on `read-tree`
happening to be a no-op there.

**Same root cause, second symptom: `/ship` suppression silently never applied on
fully-committed branches.** `CHECKPOINT_SHA` was also unset on the skip path, so Step 4 wrote an
empty `CHECKPOINT=` into `scope.txt` and Step 8.6 logged `"commit":""` to the handoff — matching
nothing, disabling the dedup that Step 8.6 exists to provide. Now set from `git rev-parse HEAD`.

Verified all three checkpoint states plus unset: the mutation check fires in every one, and Step
9's two undos gate correctly per state.

## 0.3.0 — 2026-07-27

### `upgrade-all` 0.2.0 → 0.3.0

**`/upgrade-all` never updated this marketplace's own plugins.** It refreshed marketplace
metadata with `claude plugins marketplace update`, then updated a hardcoded list of
`lattice`, `aws-core`, and `sparkpilot` — so `fresh-review` and its siblings stayed pinned at
whatever version was installed, indefinitely and silently. Found while checking why the local
install was still on `fresh-review` 0.1.0 after the 0.2.0 release.

The list now also covers `everything`, `fresh-review`, `restaurant-search`, and `upgrade-all`.
`upgrade-all` updates itself last: a new version installs into a sibling
`cache/<marketplace>/<plugin>/<version>/` directory rather than overwriting the running
script, so it is safe either way, but ordering it last removes the question entirely.

The `claude CLI not found` fallback branch was looping-ified so the skip list cannot drift out
of sync with the update list again — the previous form repeated each plugin name by hand and
would have needed a second edit that is easy to forget.

Verified against the real CLI that the `CURRENT` classifier still fires correctly: an
up-to-date plugin prints `✔ fresh-review is already at the latest version (0.2.0).`, which
matches the existing `already|up to date|up-to-date|no update` pattern. Without that check a
current plugin would have been mislabelled `UPGRADED` in every summary.

Skill description and body updated to name the plugins actually covered.

## 0.2.0 — 2026-07-27

### `fresh-review` 0.1.0 → 0.2.0

Driven by four problems observed across real runs in `vi-activate`, `lakehouse-kit`, and
`vi-ds-models`.

**The chat output buried the verdict.** The report file was written for the agents and the
user got a pointer to it. Added an **Output contract** and a new Step 8 with a fixed shape:
verdict on the first line, then every finding from every pass, deduplicated and tagged with
which passes raised it, bucketed into blockers / by-design / noise / misread. Disk is now
explicitly the archive, and "full report at `<path>`" is called out as not an acceptable
substitute for the findings.

**Every pass re-derived the same diff, and all their prose came home.** Added a **Token
discipline** section with four invariants, and a shared diff packet (`packet/diff.patch`,
`files.txt`, `stat.txt`, `scope.txt`) built once and handed to all four reviewers by path.
The orchestrator no longer reads the diff at all — Step 4 classifies risk with `grep -c` and
consumes only the counts. The biggest saving is the new compact return contract: each pass
writes its narrative to `raw/<pass>.md` and returns a fixed block of one-line findings.
Previously `/review`'s full output — dashboards, specialist merges, synthesis blocks — landed
in the orchestrator context verbatim.

**There were no logs.** `grep -rl fresh-review ~/.gstack/projects/` matched exactly one file,
and nothing from the three repos above; `$RAW_DIR` was a `mktemp -d`, so every raw report was
already gone. Runs now persist to `$REPORT_DIR/runs/<run_id>/` with the packet, raw reports,
`report.md`, and `run.json`, indexed in `runs.jsonl` (schema 2) and mirrored to the gstack
timeline. Per-pass durations, per-pass finding counts, triage bucket counts, and the previously
unrecorded exit code of the `/ship` handoff are all captured. The schema is deliberately
generic so a future cross-skill run-analysis tool can read it without a per-skill parser.

**Codex was the critical path.** It ran as two serial 5-minute passes *inside* Pass B's
`/review`, behind everything else that skill does. Hoisted out into Pass D, launched in the
same message as the three subagents so it overlaps them.

### Ported upstream from the vi-activate fork

The `vi-activate` copy at `.claude/skills/fresh-review/` had diverged with fixes the marketplace
version lacked. Three were live bugs here:

- **`AHEAD` was computed from `@{upstream}..HEAD`.** A fully pushed PR branch reports `AHEAD=0`, so
  with a clean tree the skill stopped with "nothing to review" while a complete reviewable diff sat
  in front of it. Now `$DIFF_BASE..HEAD`, with `@{upstream}` kept only as the fallback for when
  there is no `origin/$BASE` to merge-base against.
- **The index restore flattened partially staged files.** `STAGED_BEFORE` recorded path *names*, so
  restoring re-staged whole files and silently folded unstaged hunks into the index, destroying the
  split the user built. Replaced with `INDEX_TREE=$(git write-tree)` and `git read-tree`, which
  restores staged content exactly.
- **A failed checkpoint commit left everything staged.** `git add -A` runs before the commit, so
  treating a commit failure as "no checkpoint, skip the restore" never undid the `add`. The two
  undos are now independent: `git read-tree` runs whenever `git add -A` ran, `git reset --soft
  HEAD~1` only when the commit actually landed.

Also adopted: the unmerged-index guard (`INDEX_TREE=none` stops at preflight rather than
checkpointing a conflicted tree); **Step 6.5, a mechanical reviewer-mutation check** that
quarantines and reverts post-fan-out dirt, since subagents inherit the parent's tool access and
"do not fix anything" was unenforced prose; a **Pass A stop before lattice's "Step 5: Harvest
Learnings"**, which writes to the tracked `.lattice/learnings/operational-learnings.md` and blocks
on a confirmation question; a **Pass C stop after `/cso` Phase 12**, taking the findings report
without remediation; `SPAWNED_SESSION: true` as the non-interactive lever with an explicit warning
never to set `GSTACK_HEADLESS` (`gstack-session-kind` maps `headless` to `BLOCKED — stop and wait`);
the rationale for per-pass stop lists at all (the subagent reads the nested skill as executable
instructions and the last instruction wins); "Pass B is the expected offender" audit guidance; and
`.lattice/learnings/**` in allowed reads.

### Fixed

- **Run logs fragmented across worktrees.** `$REPORT_DIR` falls back to `$(git rev-parse --git-dir)`,
  which in a worktree resolves to `.git/worktrees/<name>` — so the index scattered per-worktree and
  was deleted with them, leaving cross-run analysis seeing a fraction of the history. Run directories
  still live at `$REPORT_DIR`, but `runs.jsonl` now goes to `$LOG_DIR`, pinned to
  `git rev-parse --git-common-dir` and shared by every worktree of a repo.
- **Pass B was the least isolated of the three passes.** `/review` Step 1.5 (Scope Drift
  Detection) plus Plan File Discovery and Fallback Intent Sources deliberately read plan files,
  `TODOS.md`, and the PR body via `gh pr view` in order to establish "stated intent" — exactly
  what the isolation contract forbids. Step 6's `FILES_READ:` audit could never have caught the
  `gh pr view` call, since it is not a file read. Pass B now names those steps and skips them,
  along with the Fix-First pipeline (which edits code, contradicting "do not fix anything"),
  Greptile, TODOS cross-reference, and docs staleness. The specialist dispatch and adversarial
  subagent — the reason the pass exists — are kept.
- **Pass B fanned out to nine nested subagents, most of them duplicates.** Unconstrained it
  dispatches seven `specialists/*.md`, plus Red Team (a separate conditional dispatch after Step
  4.6, triggered at `DIFF_LINES > 200` or any specialist CRITICAL), plus the always-on Step 5.7
  Claude adversarial subagent. `testing` and `maintainability` are marked always-on above 50
  changed lines and duplicate Pass A's lattice `test-quality` and `clean-code` atoms, directly
  contradicting Pass B's own instruction to skip clean-code findings. Pass B now dispatches
  exactly five: `security`, `performance`, `data-migration`, `api-contract`, and **Red Team** —
  kept because it is second-order, receiving the merged specialist findings and hunting what they
  missed on cross-cutting and integration boundaries, which is anti-correlated with every other
  pass by construction. `testing`, `maintainability`, and `design` are suppressed, and the Step 5.7
  Claude adversarial subagent reverts to its documented fallback role, running only when Codex is
  unavailable rather than as a third correlated adversarial lens. Red Team is force-activated on
  high-risk diffs, since suppressing three specialists lowers the odds of its CRITICAL trigger
  firing. All five are pointed at the shared packet rather than each running `git merge-base` and
  `git diff`, as their stock prompts instruct.
- Noted in the skill that `gstack-specialist-stats` reports `0 reviews analyzed`, so Step 4.5's
  `[GATE_CANDIDATE]` adaptive gating has never had data and scope gating is the only filter that
  actually operates — the specialist roster cannot be left to prune itself.
- **Convergence was treated as uniformly strong evidence.** Two Claude passes running similar
  checklists agreeing is one reviewer counted twice, not corroboration. The triage override now
  weights convergence by source independence — Codex-plus-Claude strongest, `cso`-plus-
  `gstack/security` moderate, `lattice`-plus-`gstack` on craft findings weak. Pass B tags each
  finding with the specialist that raised it so triage can tell these apart.
- **Codex used `codex exec`; switched to `codex review`.** `review` scopes natively via `--base`
  and emits structured severity-marked findings; `exec` returns prose needing a parse. Verified
  against codex-cli 0.145.0: `--base` and a custom `[PROMPT]` are mutually exclusive, so the
  isolation contract cannot be injected — acceptable, because a separate process running a
  different model family with no conversation history is already the strongest isolation here.
- **Codex no longer runs under a hard kill.** gstack sets the Bash tool's `timeout: 300000`,
  which burns the full budget and discards the work. It now runs backgrounded, making the budget
  a join deadline: late results land via a Step 8.5 addendum recording whether they moved the
  verdict, rather than being thrown away.
- Added `-c approval_policy="never" -c sandbox_mode="read-only"` so a background run cannot stall
  on an approval prompt (the user's `~/.codex/config.toml` sets `approval_mode = "approve"`), and
  so read-only is enforced by the process rather than by instruction. Dropped
  `--enable web_search_cached`, which adds latency and rarely pays on a diff review.
- Step numbering was non-monotonic in the workflow — the packet build was numbered before the
  checkpoint it must run after. Renumbered so the documented order matches the required order.
- Guarded the retention `rm -rf` on a non-empty `$REPORT_DIR` and an existing `runs/`.

Measured for context: `codex review --base` takes **29.6s on a completely empty diff** — process
start, one git probe, one model round trip. That floor is why it must never gate the verdict.

## 0.1.0 — 2026-07-27

Initial marketplace. Three authored skills, extracted from `~/.claude/skills/` and the
Claude Desktop skill store.

### Added

- `fresh-review` 0.1.0 — pre-commit review with producer/reviewer context separation.
- `upgrade-all` 0.2.0 — one-shot Homebrew / gstack / Claude-plugin maintenance.
- `restaurant-search` 0.1.0 — three-gate restaurant finder (area → open → verified menu).
- `everything` 0.1.0 — dependency-only meta-plugin installing all three.
- `chat-skills/restaurant-search` — claude.ai Chat variant.
- `scripts/validate.sh`, `scripts/build-chat-skills.sh`.

### Fixed during extraction

These were live defects in the skills as they sat in `~/.claude/skills/`:

- **`upgrade-all` would have broken on install.** It invoked
  `~/.claude/skills/upgrade-all/upgrade-all.sh`, but an installed plugin lives under
  `~/.claude/plugins/cache/…`, where that path does not exist. Now
  `${CLAUDE_PLUGIN_ROOT}/scripts/upgrade-all.sh`.
- **`upgrade-all` used a `triggers:` frontmatter key**, which Claude Code does not support
  and silently ignores — so those four trigger phrases were never matching anything. Folded
  into `description`, which is what routing actually reads.
- **`fresh-review` listed `Task` in `allowed-tools`.** No such tool exists; the entry was
  inert. Removed — `Agent` was already present and is the real one.
- **`fresh-review` hardcoded `~/.claude/skills/gstack/bin`** in its Step 7.5 handoff while
  its own preflight computed the same path into `$GSTACK_BIN`. The preflight now probes both
  known gstack locations (`~/.claude/skills/gstack`, `~/.gstack/repos/gstack`) and Step 7.5
  uses the resolved variable.

### Known limitations

- gstack cannot be a plugin dependency — it is a git clone, not a plugin. `fresh-review`
  detects it at preflight and degrades to a single-lens verdict when it is absent.
- Homebrew and the `claude` CLI likewise cannot be auto-provisioned; `upgrade-all` reports
  them `SKIPPED`.
- Claude Code has no install-time or post-install hook, so there is no sanctioned place to
  run provisioning at install. `SessionStart` is the only automatic entry point.
