---
name: fresh-review
description: |
  Architect-first, fresh-eyes code review. Every run starts with an architecture risk tier — low,
  medium, or high — set by a context-isolated pass that reads the code alone. Low means no
  architecture change: the code review runs on its own, with no stop. Medium and high get a short
  brief for the human, who reads architecture, not code: a before and an after diagram in the
  domain's own DDD language (bounded contexts, aggregates, services, events, outside systems — no
  class names or code), at most two paragraphs on what changed, and, when the UI changed, the
  screenshots attached to the PR. Medium goes on to the code review in the same turn; high waits
  for the user's go. The code review runs context-isolated subagents that cannot read design docs,
  intent, or prior session context: a fast implementation pass and the gstack security audit
  always, the lattice review only when the feature has a lattice design or context doc. Chat gets
  the verdict and each finding as one plain sentence about what goes wrong — the code diffs go to
  report.md, for the session that fixes them. A finding blocks only with a concrete failure
  scenario. A cross-model Codex pass runs on request ("with codex", "cross-model review") and is a
  must on high-risk changes. Triages findings against the producer-context and logs the run.

  Does NOT run gstack's `/review` army by default. On your own branch `/ship` runs it at Step 9. On
  someone else's PR it runs only with `--army` ("with the review army", "full army").

  Use when the user asks to "fresh review", "fresh-eyes review", "review my changes", "pre-commit
  review", "review before commit", "review with no bias", "independent review", "what did I miss",
  "check my work before I commit", "context-free review", "what does this change do", "explain
  this PR", "architecture review", or "review with fresh eyes", or names a PR by number or URL
  ("review PR 42", "look at github.com/o/r/pull/42"). Proactively suggest before any /ship,
  /land-and-deploy, or manual git commit when the diff exceeds ~50 lines or touches auth,
  payments, migrations, or security-sensitive code.

  Has a **stack** mode for a stack of PRs: it reviews nothing itself, plans which PRs are reviewed
  alone and which together, prints one handoff prompt per review for the user to run in a new
  session, and tracks the stack's verdict. Use it when the user asks to "review this stack",
  "review the stack for PR 42", "review PRs 41 42 43", or names two or more PRs.

  PR reviews and stack units also support a **re-review** (`--delta`): it reviews only what changed
  since the last review and checks that each earlier blocker is fixed. Use it when the user asks
  to "re-review PR 42", "review PR 42 again", or "review the fixes on PR 42".

  This is the right tool whenever the producer-Claude and the reviewer-Claude would otherwise be the
  same instance with the same context — the entire point is to break that bias. Do NOT call
  /lattice:review or /cso directly when the user wants fresh eyes; those run inside the producer
  context and will rationalize away the producer's own choices.
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - Agent
  - Write
  - AskUserQuestion
---

# fresh-review

Tell the architect what changed in the architecture. Review the code with fresh eyes.

## Who reads this

The user is an architect. They read parts and how the parts connect, not code. So:

- **The brief is in domain words.** Bounded contexts, aggregates, services, events, stores, outside systems. Never a class, function, file, or table name.
- **Findings in chat are plain sentences** about what goes wrong, for whom, and when. The code diffs live in `report.md`, where the session that fixes them reads them.
- **You know the code better than the user.** Do not ask them to judge a line of code. Ask them only about architecture, and only on a high-risk change.

## Modes

| The user's words | Preflight flags | Subject of the review |
|---|---|---|
| "fresh review", "review before I commit", "what does this change do" | *(none)* | your branch |
| "review PR 42", a `github.com/…/pull/42` URL | `--pr 42` | PR 42's head commit |
| "review this stack", "review the stack for PR 42", "review PRs 41 42 43" | `--stack "<refs>"` | nothing — this session only plans |
| "re-review PR 42", "review PR 42 again", "review the fixes on PR 42" | `--pr 42 --delta` | only what changed on PR 42 since its last review |

Every mode except stack runs the same flow: risk tier, then the brief (medium and high), then the code review. Whenever the review subject has a PR, the run also gathers PR context (Step 4.7), shows the PR's screenshots in the brief when the UI changed, and, if the PR carried static-analysis findings, verifies each was handled (Pass W).

Resolve the mode once, from the invocation, and pass it to `fr-preflight.sh`. Do not re-derive it later.

- **Explicit flags win.** When the request already carries `--pr`, `--since-pr`, or `--stack`, pass them through verbatim and do not re-read the numbers in it. A stack handoff starts with `--pr 43 --since-pr 42`: that is one pr-remote review, not a stack.
- The word **stack**, or **two or more** PR numbers or pull URLs, means `--stack "<the refs>"`. One ref with the word stack ("review the stack for PR 42") is enough: the script finds the rest of the stack.
- A **number or pull URL** anywhere in the request means `--pr <that>`.
- **Re-review words** with a PR ref — "re-review", "review again", "review the fixes", "only what changed since the last review" — add `--delta`. With no PR ref there is nothing to re-review against: say that re-review works for PRs and stack units only, and run the normal review.
- Everything else is the default. `--mode pr` is still accepted and runs the default flow.
- **`--army`** when the request asks for gstack's review army ("with the review army", "full army", "run /review too"). It only matters in pr-remote.
- **`--understood`** when the user says not to stop for approval ("I know this change", "don't wait for me", "no need to approve"). A high-risk change then shows its brief and goes on to the code review. `--arch-approved` is the old name and still works.

### The risk tier

Pass U (Step 4.8) reads the diff alone and sets one tier for the change:

| Tier | What it means | What the user gets | Does the run stop? |
|---|---|---|---|
| **low** | no architecture change — logic, fixes, tests, docs, config values, a refactor inside one part | one line, then the code review result | no |
| **medium** | the architecture changes inside one bounded context — a new or removed part, a new link between parts, a changed internal contract | the brief, then the code review result, in the same turn | no |
| **high** | the change crosses a boundary or is hard to undo — a new or split context, a contract other contexts or clients use, data ownership moves, a new outside system, auth or trust boundaries, a migration that changes what is stored | the brief, then a stop for the user's go | **yes**, until the user says go (or `--understood`) |

A high tier also makes Codex a must (`CODEX_REASON=tier`).

The tier is not the same as the mechanical `RISK` (`normal`/`high`, from `fr-packet.sh`). `RISK` counts risky patterns (auth, payment, migration, IaC paths, large diffs) and sets the code review's depth: `/cso --comprehensive` and a required Codex. The tier is about architecture and sets what the human sees. A one-line change to an auth check is tier low and `RISK: high`: no brief, a deep code review.

### The Codex opt-in

**Codex (Pass C) is off by default.** It is a separate `--codex` flag, orthogonal to the mode. Resolve it once, from the invocation:

- Pass `--codex` when the request names Codex or asks for cross-model coverage: "with codex", "codex pass", "cross-model review", "run codex too", "add a second model".
- Otherwise omit it. Do not add `--codex` yourself.
- **It becomes a must** in two ways, and the verdict then waits for it with no join budget: `fr-packet.sh` classifies `RISK: high` (it sets `CODEX_REQUESTED=1`, `CODEX_REASON=risk`), or Pass U sets the tier `high` (Step 4.8 sets `CODEX_REQUESTED=1`, `CODEX_REASON=tier`).
- The flag is a request, not a guarantee: Pass C runs only when `CODEX_REQUESTED: 1` **and** `HAS_CODEX: 1`. When it was asked for or required but `codex` is not on PATH, say so. On a required run that is a loud gap (Step 8).

### pr-local and pr-remote

`--pr <ref>` moves the subject of the review off your branch, and several things follow from no longer being the author:

| | your branch | `--pr <ref>` (**pr-remote**) |
|---|---|---|
| What is reviewed | merge-base..worktree | the PR head, fetched fresh |
| Source files opened from | your checkout | a detached worktree at the PR head (`SOURCE_ROOT`) |
| WIP checkpoint (Step 3) | runs | **skipped** — nothing of yours is being reviewed |
| Verdict vocabulary | `COMMIT` / `COMMIT-WITH-FIXES` / `DO-NOT-COMMIT` | `APPROVE` / `APPROVE-WITH-COMMENTS` / `REQUEST-CHANGES` |
| Triage bucket 2 ("by design") | may cite this session's decisions | **may not** — you have no intent knowledge |
| After the report | offer to fix the findings | the findings are asks for the author |
| Handoff to `/ship` (Step 8.6) | runs | **skipped** — you are not shipping this |
| gstack `/review` army (Pass R) | not run — `/ship` Step 9 owns it | **only with `--army`** |

### Stack mode and re-review

- **Stack mode** (`--stack`) turns this session into an orchestrator. It reviews no code: it plans review units, prints one handoff per unit for the user to run in a new session, and tracks the `STACK REPORT` lines the user pastes back. A stack of one PR is reviewed here as a normal `--pr` run. The rules are in `$FR_REFS/stack.md`; Step 1 says when to read it.
- **Re-review** (`--delta`, pr-remote and stack units only) reviews only what changed since the last recorded review of the PR, and Pass F checks each earlier blocker. The tier is the delta's tier. The rules are in `$FR_REFS/delta.md`; Step 1.6 says when to read it.

## Configuration

```
LATTICE_REVIEW_CMD="/lattice:review"     # Lattice standards conformance (plugin-namespaced)
CSO_CMD="/cso --diff"                    # gstack security audit, scoped to branch changes
CODEX_JOIN_BUDGET=240                    # seconds to wait for Codex after the Claude passes return
FR_RUN_RETENTION=20                      # run directories kept before pruning (env var, read by fr-log.sh)
DDD_DOC=".lattice/standards/ddd-principles.md"   # vocabulary for Pass U; resolved by fr-ddd-vocab.sh
FR_UI_MAX_IMAGES=6                       # PR screenshots shown in the brief (env var, read by fr-ui-images.sh)
FR_STACK_SMALL_LINES=80                  # stack mode: a PR this small joins the unit below it (env var)
FR_HANDOFF_CMD="/fresh-review:review"    # stack mode: the command each handoff starts with (env var)
```

- Review scope is resolved by `fr-preflight.sh`: `branch` (merge-base..worktree) when an `origin/<base>` exists, `working` otherwise, or `pr` (merge-base..PR head) when a PR ref was given.
- **Lattice (Pass A) runs only when the feature has a lattice design or context doc** (Step 4.4).
- `/cso --diff` keeps the 8/10 confidence gate. `RISK: high` upgrades it to `--diff --comprehensive`.
- **Re-review records** live in `$LOG_DIR/reviews/`, next to `runs.jsonl`, and are never pruned.
- **PR context** (Step 4.7) is gathered whenever a PR exists, for triage, the brief's screenshots, and Pass W only — never for the isolated passes. It needs `gh`; with no PR or no `gh` it skips itself.

## gstack's `/review` is not a default pass

On your own branch `/ship` runs `/review` at its Step 9, so this skill never runs it there. On someone else's PR it runs only with `--army` (Pass R): it costs a median 15 minutes and about 30% of a run's tokens. The plugin's `references/ship-dispatch-gate.md` trims what ship would repeat after this skill.

## Output contract

Two audiences, two artifacts. Do not confuse them.

- **Chat is for the architect, and it is kept lean.** First the tier: one line for low, the brief for medium and high (Step 4.8). After the code review: the verdict on its own line, then one plain sentence per blocker and should-fix finding, one line per by-design finding, and the count of comments to drop. No code blocks in the review — the diffs are in `report.md`. Chat reads like a normal reply to a person: short sentences, bullets with bold labels, links. Every file reference is a link.
- **Disk carries the long form.** The brief's full Pass U report, every finding with its ` ```diff ` block, the comment list, the noise and misread findings, the coverage notes, raw pass reports, the diff packet, and the run log all live in the run directory (`report.md` and `raw/`).
- **Nothing is for GitHub.** No mode posts, comments, or edits a PR. See "What this skill does NOT do".

## Token discipline

Five invariants. Every step below is built around them; violating one silently makes the run cost several times what it should.

1. **The orchestrator never loads the diff** — nor the DDD principles document, nor the PR's own content beyond what triage needs. `fr-packet.sh` classifies risk with `grep -c` over the patch and prints only counts; `fr-ddd-vocab.sh` extracts the vocabulary sections into a brief and prints only its line count; `fr-pr-context.sh` writes the PR description and discussion to disk and prints only counts (`DISCUSSION_LINES` among them). The one producer-side read is triage's: `body.md` always, `discussion.md` bounded by its line count (skim when large). The static-analysis material is never read by the orchestrator at all — it is handed to Pass W by path.
2. **Reviewers read the packet, not git — and never the PR context.** The diff is materialized once (Step 4) and every isolated pass is handed the same file paths. No isolated pass re-derives scope, runs `git diff`, or opens `pr-context/`. Pass W is the sole exception on both counts: it reads `pr-context/` because verifying analyzer findings is its whole job, and it is not a critic.
3. **Passes return compact findings; prose goes to disk.** Each pass writes its full report to `$RUN_DIR/raw/` and returns only the fixed-format block in Step 5.
4. **Raw reports are not read back.** Triage runs on the compact blocks. Open a raw report only to disambiguate one specific finding, and read only that finding's section.
5. **Nothing heavy enters the orchestrator by accident.** Never open a rendered PNG or a PR screenshot with Read — send it with `SendUserFile`, which does not put the image in your context; an image costs ~40k tokens. Never re-read this SKILL.md mid-run; it is already loaded.

The same principle governs the shell work: every mechanical step is a script in `${CLAUDE_PLUGIN_ROOT}/scripts/` that prints a small delimited key block. Read the block, not the machinery. Do not reimplement a script's logic inline — the scripts are where the gating rules are actually enforced.

## Workflow

Steps run in order. Step 5 is one parallel fan-out; everything else is sequential. In stack mode only Steps 0, 1, and **S** (in `stack.md`) run — Step S replaces the rest, except for a stack of one PR, which Step S turns back into a normal `--pr` run. Otherwise, steps are conditional where their heading says so: **1.5** and **1.6** run in pr-remote, **4.7** (PR context) runs when a PR is discoverable, **4.8** (tier and brief) runs always and stops for the user only on a high tier, **3** and **8.6** are skipped in pr-remote, and Step 5's fan-out grows with the run — Pass A when there is a lattice context, Pass R in pr-remote with `--army`, Pass W when the PR carried analyzer findings, Pass F on a re-review with earlier blockers, and Pass C when Codex is requested or required.

Every script takes `$RUN_DIR` and reads the rest of its inputs from `$RUN_DIR/state.env`, which `fr-preflight.sh` creates and later scripts append to. You never have to thread variables between Bash calls by hand — and because state lives on disk, a run interrupted mid-way can still be restored on the next turn.

**Reference files.** Mode- and pass-specific rules live next to this file, in `$FR_REFS` = `${CLAUDE_PLUGIN_ROOT}/skills/fresh-review/references` (use the root Step 0 printed). Read a reference file only when a step below says so, and only once per run. A default review of your own branch reads only `run-log.md`, at Step 10.

<!-- FR:BOOTSTRAP:START -->
### Step 0: Resolve the plugin root (bootstrap)

Every script below is addressed as `${CLAUDE_PLUGIN_ROOT}/scripts/…`. Claude Code exports that variable into a plugin's own commands and hooks, but **not** into the ad-hoc Bash-tool shell this skill body drives once the Skill tool has loaded — and each Bash-tool call is a fresh shell that inherits nothing from the previous one. So it is routinely empty here, and an empty value collapses every call to `bash "/scripts/fr-*.sh"`, which fails. Resolve it once, now, and do not assume it survives into the next call.

Run this before Step 1. It keeps an ambient value when Claude Code did provide one, and otherwise locates the plugin deterministically. When the Skill tool printed `Base directory for this skill: <dir>` above this body, set `FR_SKILL_BASE="<dir>"` at the top of the block: that is the copy whose instructions you are reading, so its scripts are the ones that match them.

```bash
FR_SKILL_BASE="${FR_SKILL_BASE:-}"
CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$CLAUDE_PLUGIN_ROOT" ] || [ ! -f "$CLAUDE_PLUGIN_ROOT/scripts/fr-preflight.sh" ]; then
  for c in \
      "${FR_SKILL_BASE:+$FR_SKILL_BASE/../..}" \
      "$(git rev-parse --show-toplevel 2>/dev/null)/plugins/fresh-review" \
      "$HOME/.claude/plugins/marketplaces/ShuratCode-skills/plugins/fresh-review" \
      $(ls -d "$HOME"/.claude/plugins/cache/ShuratCode-skills/fresh-review/*/ 2>/dev/null | sort -Vr); do
    [ -f "$c/scripts/fr-preflight.sh" ] && CLAUDE_PLUGIN_ROOT="$(cd "$c" && pwd)" && break
  done
fi
[ -f "$CLAUDE_PLUGIN_ROOT/scripts/fr-preflight.sh" ] \
  && echo "FR_PLUGIN_ROOT: $CLAUDE_PLUGIN_ROOT" \
  && echo "FR_PLUGIN_VERSION: $(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json" | head -1)" \
  || echo "FR_PLUGIN_ROOT: UNRESOLVED"
```

`FR_PLUGIN_VERSION` is the version of the copy that actually runs, read from that root's own `plugin.json` — not the marketplace cache. The Claude desktop app runs each session from its own snapshot of the plugin (under `~/Library/Application Support/Claude/local-agent-mode-sessions/…/rpm/plugin_<id>/`), and that snapshot can lag the installed version. So when a user asks which version ran, answer with this line, not with the cache.

**On `FR_PLUGIN_ROOT: UNRESOLVED`, stop** and tell the user the fresh-review plugin scripts could not be located — the install looks broken. Every later step would fail the same way.

Otherwise carry the resolved path into Step 1: run its `fr-preflight.sh` command with the variable set **in that same shell**, because the fresh shell will not have it — prefix the command with `CLAUDE_PLUGIN_ROOT="<the resolved path>"`. You resolve it exactly once. From Step 1 on, `fr-preflight.sh` has written the root into `state.env`, and every later step below already sources `state.env` before its script call, which restores the variable into that call's own shell — no re-resolution, no threading by hand.
<!-- FR:BOOTSTRAP:END -->

### Step 1: Preflight

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh"                   # your branch
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh" --pr 42            # pr-remote
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh" --codex            # your branch + Codex (Pass C)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh" --pr 42 --codex    # pr-remote + Codex
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh" --understood       # a high tier does not stop for approval
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh" --pr 42 --army     # pr-remote + the gstack review army (Pass R)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh" --stack "42"       # stack mode: find the stack around PR 42
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh" --stack "41,42,43" # stack mode: exactly these PRs
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh" --pr 43 --since-pr 42  # one review of PRs 42..43 (a stack unit)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh" --pr 42 --delta     # re-review: only what changed since the last review
```

<!-- FR:BOOTSTRAP:START -->
Run this with the plugin root from Step 0 set in the same shell — prefix the command with `CLAUDE_PLUGIN_ROOT="<the path Step 0 resolved>"`, since this fresh shell does not carry it.
<!-- FR:BOOTSTRAP:END -->
This probes the repo, resolves the review scope, creates the run directory, and writes `state.env` — including the plugin root itself, so no later step has to resolve it again. Export `RUN_DIR` from its output — every later script takes it as `$1`. Pass the flags from the Modes table verbatim, add `--codex` only when the invocation asked for it, `--understood` only when the user said not to stop for approval, and `--army` only when they asked for the review army; the script rejects an unknown flag or mode with a non-zero exit rather than falling back to a default, because a silently-defaulted `--pr` would review the local branch under someone else's PR number.

**In stack mode, read `$FR_REFS/stack.md` now and follow its Step S.** It replaces every other step (a stack of one PR comes back here as a `--pr` run).

On `STATUS: stop`, tell the user and stop. `STOP_REASON` is one of:

- `not_a_repo` — nothing to do here.
- `nothing_to_review` — no dirt and no commits the base branch lacks.
- `unmerged_index` — a conflict is in progress. Do **not** checkpoint a conflicted tree. Resolve it, then re-run.

Neither of the last two can fire under `--pr`: both describe the local tree, which is not the subject of a pr-remote review.

Tool-availability accounting — state each of these up front, never silently:

- `HAS_GSTACK: 0` → `/cso` does not exist here. **A critic pass cannot run.** Say so plainly, run Pass I (plus Pass A and Pass C when they apply), label the verdict reduced-lens.
- `CODEX_REQUESTED: 0` → the run did not ask for Codex. Step 4 or Step 4.8 may still turn it on. If it stays `0`, Pass C is absent by choice, not by failure. Do not mention missing cross-model coverage as a gap. Only note, once, that `--codex` is available.
- `CODEX_REQUESTED: 1` with `HAS_CODEX: 0` → Codex was asked for but `codex` is not on PATH, so Pass C **cannot** run. Say so plainly, run the Claude critics, label the verdict reduced-lens, and do not substitute a Claude pass for it. Fix is `codex login` (or installing the CLI) and re-run.
- `HAS_GH: 0` → pr-remote is impossible, and the brief has no PR screenshots. Only matters when a PR ref was given; Step 1.5 stops on it.
- `DELTA_REQUESTED: 1` → the user asked for a re-review. Step 1.6 decides whether a delta is possible. `--delta` without `--pr` is rejected with exit 2.
- `PLUGIN_STALE: yes` means a newer version (`PLUGIN_INSTALLED`) is installed than the one this session loaded. Say once: `⚠ this session runs fresh-review <PLUGIN_VERSION>; <PLUGIN_INSTALLED> is installed. Start a new session to use it.` Then go on.
- `ARCH_APPROVED: 1` → `--understood`: a high tier shows its brief and does not stop.
- `ARMY_REQUESTED: 1` → Pass R runs in pr-remote when `HAS_GSTACK: 1`. On your own branch it does nothing: `/ship` runs the army.
- `CODEX_CFG: unknown` → `gstack-config` was not found. Report unknown, never guess `enabled`. This setting gates *gstack's* internal Codex, not ours.

Two other outputs matter later:

- `DIRTY: 0` with `AHEAD > 0` → the branch carries commits the base does not, pushed or not. Review them: the checkpoint self-skips in Step 3, scope stays `branch`.
- `INDEX_TREE` is a real tree object written from the pre-review index, so it carries the staged *content* of every path. Step 9 restores from it **exactly**, including partially staged files.

The run directory persists, so a run can be analyzed afterward. It lives under `.fresh-review/` when that path is gitignored, and under the git dir otherwise; the script never edits `.gitignore`. `LOG_DIR` is the common git dir, so the run index survives worktree removal.

### Step 1.5: Resolve the PR (pr-remote only)

Skip unless `PR_REF` is set. Otherwise read `$FR_REFS/pr-remote.md` now and run its Step 1.5. Keep it for the rest of the run: it also holds the review record that Step 10 writes and the pr-remote failure modes.

### Step 1.6: Resolve the delta (pr-remote only)

Skip unless `PR_REF` is set. Run it on every pr-remote run, with or without `--delta`:

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-delta.sh" "$RUN_DIR"
```

- `DELTA: off` (no `--delta`) → nothing changes. When `PRIOR_REVIEW` is not `none`, say once: `PR #<n> was reviewed before at <PRIOR_HEAD short sha> (<PRIOR_VERDICT>). Say "re-review" to review only the changes since then.` Then go on with the full review.
- Any other value (`applied`, `ask`, `full`, `none`) → read `$FR_REFS/delta.md` and follow its Step 1.6. Keep it for the rest of the run: it also holds Pass F and the re-review failure modes.

### Step 2: State the scope

`fr-preflight.sh` already printed `REVIEW_SCOPE` and `DIFF_CMD`. Say them out loud — one canonical scope string, handed identically to every reviewer so their findings are comparable. State `SOURCE_ROOT` too whenever it is not the repo root: reading the right path in the wrong tree returns plausible file contents from the wrong commit.

### Step 3: WIP checkpoint

**Skip this step entirely in pr-remote mode** — `CHECKPOINT` is already `pr_remote`, and there is nothing of yours under review.

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-checkpoint.sh" "$RUN_DIR"
```

Commits everything with `--no-verify` (this skill IS the review), or self-skips when the tree is already clean. `CHECKPOINT` comes back as exactly one of `committed`, `skipped`, `failed`. `CHECKPOINT_SHA` is always set.

**What the checkpoint is for:** making untracked files visible. A brand-new file does not appear in `git diff` at all, so without staging it the reviewers would never see the code most likely to contain fresh bugs. It also pins a stable SHA for the audit trail and for Codex's `--commit` scoping.

On `CHECKPOINT: failed`, continue in no-checkpoint mode: the packet builds from `git diff HEAD` / `git diff $DIFF_BASE`, untracked files go unreviewed (record that in the report), and the script has already written `raw/pre-fanout.status` as the baseline the Step 6.5 mutation check needs. **Step 9's index restore still runs** — only the commit-reset half is skipped.

**Do not edit anything from here until Step 9 completes.** A formatter-on-save or codegen watcher firing mid-review produces findings with stale line numbers.

### Step 4: Build the shared diff packet and classify the mechanical risk

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-packet.sh" "$RUN_DIR"
```

Materializes the scope **once** into `$RUN_DIR/packet/` — `diff.patch`, `stat.txt`, `files.txt`, `scope.txt` — and classifies the mechanical risk by pattern count over the patch, so the orchestrator sees integers rather than a diff. `scope.txt` also names `BEFORE_REV`, the commit Pass U reads the "before" state from.

`RISK: high` fires on any auth/payment/migration/secret path hit, any IaC file, more than three body hits, or more than 300 changed lines. It sets `/cso` to `--diff --comprehensive` and makes Codex a must. The packet script prints `CODEX_REQUESTED` and `CODEX_REASON` after it applies this rule.

State the file count out loud. If `LINES` exceeds ~2000, warn that reviewer quality degrades at that size and that a re-run scoped to a subdirectory reads more carefully — then **proceed anyway**. This skill stops for an answer in two places only: a high tier (Step 4.8) and a `--delta` re-review whose delta needs the user's choice (Step 1.6).

### Step 4.4: Lattice context and added comments

Two cheap mechanical checks over the packet. Run both in one Bash call:

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-lattice-detect.sh" "$RUN_DIR"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-comments.sh" "$RUN_DIR"
```

**Lattice context.** `LATTICE_CONTEXT: yes` means this change has a lattice design or context doc, so Pass A runs in Step 5. `LATTICE_REASON` says how it matched: `diff_touches_context`, `branch_match`, or `names_changed_files`. `no` → Pass A does not run, and that is not a gap: say `lattice: not run — no lattice context for this change` once in `report.md`. **Never open the doc it names** — it is intent.

**Added comments.** `fr-comments.sh` lists every comment and docstring the diff *adds* into `packet/comments.tsv` (`file`, `start`, `end`, `kind`, `text`). Tool directives (`noqa`, `type: ignore`, `eslint-disable`, shebangs, license headers) are left out. Read `comments.tsv` in Step 10 for `report.md`, not now. `COMMENT_BLOCKS: 0` → nothing to drop.

### Step 4.5: Resolve the domain vocabulary

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-ddd-vocab.sh" "$RUN_DIR"
```

Decides which vocabulary Pass U's diagrams speak in and materializes it as `packet/ddd.md`:

| `VOCAB` | Source | What the diagrams can claim |
|---|---|---|
| `ddd-principles` | `.lattice/standards/ddd-principles.md` under `SOURCE_ROOT` | the repo's real bounded contexts and ubiquitous language |
| `atom-defaults` | no document — generic tactical terms + nouns inferred from the diff | structural terms only |

`GLOSSARY` refines the first row (`extracted` or `headings_only`); `DDD_MODE` (`overlay` / `override`) tells Pass U whether generic DDD terms are still in play.

**State `VOCAB` under the brief when it is `atom-defaults`**, in one line: `Context names are inferred from the code; run /lattice:ddd-refiner to give the diagrams the repo's own language.` A diagram in the repo's own language and one in textbook terms look alike and are worth very different amounts.

### Step 4.6: UI detection

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-ui-detect.sh" "$RUN_DIR"
```

Reads only the packet's file list and prints `FRONTEND_HITS` — whether the change touches UI code (component frameworks, stylesheets, or files under a conventional UI directory) — and `UI_REASON`. **It never launches an app**, and nothing in this skill does: launching a review tree runs code that may be untrusted, with your credentials. The brief's screenshots come from the PR only (Step 4.8b).

### Step 4.7: Gather PR context (whenever a PR exists)

Run this whenever a PR is discoverable — in every mode. It reads the PR's description, its human discussion, and any static-analysis bot findings into `$RUN_DIR/pr-context/` **for the producer side only**. Nothing it writes ever reaches an isolated pass.

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-pr-context.sh" "$RUN_DIR"
```

`PR_CONTEXT` comes back as exactly one of:

- `present` → a PR was found (already resolved in pr-remote, or discovered from the current branch's open PR). `body.md`, `discussion.md`, and `sa-findings.md` are written. For a stack unit (`STACK_PRS` holds more than one PR), each file has a section per PR. Read the printed keys, not the files.
- `none` → no PR for this branch. The normal pre-commit case. Proceed.
- `unavailable` → `gh` is missing or a call failed (`REASON` says which). State it once and proceed. It is never a blocker.

`SA_PRESENT: yes` with `SA_TOOL: <names>` → **Pass W runs in Step 5** to verify each analyzer finding was fixed, suppressed, or dismissed. `SA_PRESENT: no` → Pass W does not run; it is not a gap.

### Step 4.8: Risk tier and the architecture brief

Three parts, in order: classify (Pass U), show, then go on or stop.

#### 4.8a: Pass U — risk tier and brief

**Pass U runs alone, before any other reviewer.** Launch it with `model: $MODEL_U` (see "Subagent models" in Step 5), in its own message: one subagent, no other subagent, no Codex command, no Step 5 work. Its prompt is the Step 5 isolation contract, verbatim, followed by this task, which replaces the contract's return-format block:

> Your job is not to find defects. Your job is to judge whether this change changes the architecture, and when it does, to show the architecture before and after to a software architect who will not read the code. Read `{{RUN_DIR}}/packet/ddd.md` first — the repo's domain vocabulary — then `diff.patch`. Open a source file from `{{SOURCE_ROOT}}` only to learn what an existing part is or who uses it. To read a file as it was before the change, run `git -C {{SOURCE_ROOT}} show <BEFORE_REV from scope.txt>:<path>` — the only git command you may run.
>
> When `scope.txt` has `DELTA=since-last-review`, "this change" means only the diff: what changed since the last review.
>
> **Architecture** here means the parts of the system and how they connect: bounded contexts; aggregates and the entities they own; domain services, application services, and use cases; domain events; the contracts between parts (APIs, events, messages, schemas, file formats, CLIs); data ownership (which part stores what); outside systems (third-party services, queues, stores); and the cross-cutting mechanisms that change how parts connect (caching, retries, auth, transactions, background jobs).
>
> **Set one tier:**
>
> - `low` — no architecture change. Logic inside a part, a bug fix, tests, docs, formatting, config values, a version bump, a refactor that keeps the same parts, links, and contracts, or new behavior inside an existing part that uses only the links it already had.
> - `medium` — the architecture changes inside one bounded context: a part is added or removed (an aggregate, a service, a use case, a store, a job); a new link between existing parts; a changed contract that only this context uses; a new cross-cutting mechanism inside this context.
> - `high` — the change crosses a boundary or is hard to undo: a new, split, or merged bounded context; a changed contract that another context or an outside client uses; data ownership moves from one part to another; a new outside system; a change to auth or a trust boundary; a migration that changes what is stored.
>
> The worst item decides. When unsure between two tiers, pick the higher one.
>
> For `low`, write the one-sentence REASON and stop: SUMMARY, PARTS, BEFORE, and AFTER are `none`.
>
> For `medium` and `high`, write:
>
> 1. **REASON** — one sentence: the item that sets the tier, in domain words.
> 2. **SUMMARY** — at most two short paragraphs, in plain domain words. The first says what changed in the architecture and what the system can do now that it could not do before. The second, only when there is one, says what the change costs at the architecture level: new coupling, a new dependency, data that now lives in two places, a contract others must now follow, something that is hard to undo. No code names, no edge cases, no code quality — those are the code review's job. No empty verbs: "refactored", "updated", "improved" say nothing.
> 3. **PARTS** — each part the change adds, removes, or changes, in a few domain words, marked `added`, `removed`, or `changed`. When `{{RUN_DIR}}/delta/prior-architecture.md` exists, read it — the only file under `{{RUN_DIR}}/delta/` you may read — and add `seen` to a part that is the same architecture choice as one there; otherwise add `new`. When unsure, `new`.
> 4. **BEFORE** and **AFTER** — two Mermaid `flowchart LR` diagrams of the same area, before and after the change. Rules:
>    - **Domain words only.** Name each node with a term from `ddd.md` when it has one, else a plain domain noun ("Order", "Billing", "Payment provider"). Never a class, function, variable, file, table, queue, or library name, and no code identifier in any casing (not `OrderService`, not `order_repo`). A product name is allowed for an outside system ("Stripe").
>    - One `subgraph` per bounded context, titled with the context's name. Outside systems sit outside every subgraph.
>    - Node shapes: aggregate or entity `id[Name]`, service or use case `id(Name)`, domain event `id>Name]`, store `id[(Name)]`, outside system `id[/Name/]`.
>    - Every edge has a short label in domain words: `-->|places|`, `-->|publishes|`, `-->|listens to|`, `-->|reads|`, `-->|owns|`.
>    - Use the same node ids and the same order in both diagrams, so the two read side by side.
>    - In AFTER, mark added nodes `:::added` and changed nodes `:::changed`, and draw new links with `==>`. In BEFORE, mark the nodes the change removes `:::removed`. End each diagram with the class lines it uses: `classDef added stroke:#2e7d32,stroke-width:3px`, `classDef changed stroke:#ef6c00,stroke-width:3px`, `classDef removed stroke:#c62828,stroke-dasharray:5 5`.
>    - Show only the parts the change touches and their direct neighbors: at most ~10 nodes each. When a part is new, BEFORE still shows the neighbors it will connect to.
>    - Keep each diagram valid Mermaid — it will be rendered. Quote any label with punctuation. No HTML.
>
> Write your full report to `{{RUN_DIR}}/raw/architecture.md`. Return *only* this block:
>
> ````
> PASS: architecture
> STATUS: ok | partial | failed
> TIER: low | medium | high
> REASON: <one sentence>
> ---
> SUMMARY: <one or two short paragraphs — or "none">
> ---
> PARTS
> - P1: <part in domain words> | added | removed | changed | new | seen: <earlier part>
> (or "none")
> ---
> BEFORE: <one fenced mermaid flowchart block, fence and all — or "none">
> ---
> AFTER: <one fenced mermaid flowchart block, fence and all — or "none">
> ---
> NOTES: <at most two lines, only if something anomalous happened>
> FILES_READ: <comma-separated paths you opened>
> ````

Audit Pass U's `FILES_READ` against the forbidden list now, by the Step 6 rules. Pass U may read `delta/prior-architecture.md`; any other `delta/` path is a leak. **A Pass U leak is the worst leak there is**: a brief built from a plan, a PR title, or `pr-context/` restates the author's claim instead of the code. On a leak, re-spawn it once; on a second leak, prefix the brief `[intent-contaminated]` and say so.

Then record the tier, and on a high tier make Codex a must:

```bash
printf "%s\n" "TIER='<low|medium|high>'" >> "$RUN_DIR/state.env"
. "$RUN_DIR/state.env"; [ "$TIER" = high ] && [ "$CODEX_REQUESTED" != 1 ] \
  && printf "%s\n" "CODEX_REQUESTED='1'" "CODEX_REASON='tier'" >> "$RUN_DIR/state.env"
```

Then branch:

- `STATUS: failed`, or no block → record `TIER='unknown'` and `ARCH_GATE='failed'`, print `⚠ Risk tier unknown — the architecture pass failed. Running the code review.` and go to Step 5. Name it in the Step 8 reduced-coverage line. The brief never blocks the review of a change it could not read.
- `TIER: low` → print one line: `**Risk: low.** No architecture change — <REASON>. Running the code review.` Record `ARCH_GATE='auto'` and go to Step 5 in the same turn.
- `TIER: medium` → show the brief (4.8b). Record `ARCH_GATE='shown'`, print `Running the code review now.`, and go to Step 5 in the same turn.
- `TIER: high` → show the brief (4.8b), then 4.8c.

#### 4.8b: Show the brief

Write it as a normal chat reply in this shape. The fence only shows the shape — do not print it:

````text
**Risk: <medium | high>.** <REASON>   (<branch>, or PR #<n>: <title>)

**Before**
<the rendered BEFORE diagram>

**After**
<the rendered AFTER diagram>

<SUMMARY, verbatim>

**UI**   (only when FRONTEND_HITS is above 0)
<the PR screenshots, or one line saying why there are none>

⚠ The PR title says <x>; the change does <y>.   (only when they disagree)
````

Rules:

- **No code block around the brief.** It is normal chat text. The only code blocks it may hold are ` ```mermaid ` fallbacks.
- **Print Pass U's REASON and SUMMARY verbatim.** Do not rewrite, "improve", or merge them with what you know. You hold the producer context; Pass U does not, and that is the point.
- **Render the diagrams in Excalidraw, do not print their source.** Write the BEFORE source (without the fence) to `$RUN_DIR/ui/before.mmd` and the AFTER source to `$RUN_DIR/ui/after.mmd`, then:

  ```bash
  mkdir -p "$RUN_DIR/ui"
  . "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-diagrams.sh" "$RUN_DIR"
  ```

  The script uses gstack's offline `/diagram` bundle to turn each diagram into an `.excalidraw` scene. When the scene is editable box by box, the PNG is drawn from it (`DIAGRAM_<x>: excalidraw`). Bounded-context subgraphs do not import box by box — the scene holds one image — so those PNGs come from `mmdc`, the Mermaid CLI (`DIAGRAM_<x>: mermaid`). It never rasterizes Mermaid's SVG directly: that path draws black boxes with no labels. It prints `DIAGRAM_before` and `DIAGRAM_after`: `excalidraw`, `mermaid`, `failed`, or `none`.

  - **Show each PNG** with `SendUserFile` and `display: "render"`, the BEFORE PNG under **Before** and the AFTER PNG under **After**. Never open a PNG in Preview or with `open`. When the user asked to see the diagrams in the terminal, run `imgcat "<PNG path>"` instead. Where `SendUserFile` does not exist, print the PNG paths and say once that the user can view them with `imgcat`.
  - **Link the Excalidraw file** (`EXCALIDRAW_<x>`) under each heading, so the user can open it at excalidraw.com. When `EDITABLE_<x>: no`, add `(opens as one image)`.
  - **`failed`** → print that diagram's ` ```mermaid ` fence instead — one or the other, never both.
  - Do not hand-fix invalid Mermaid; a diagram you drew carries your knowledge of the intent.
- **UI screenshots come from the PR, never from running the app.** When `FRONTEND_HITS` is above 0 and `PR_CONTEXT: present`, run:

  ```bash
  . "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-ui-images.sh" "$RUN_DIR"
  ```

  It takes the image links from the PR description and the PR author's own comments, downloads at most `FR_UI_MAX_IMAGES` of them from GitHub's attachment hosts only, keeps a file only when it really is a PNG, JPEG, GIF, or WebP image, and prints `UI_IMAGES: <n>` with one `IMAGE_<k>: <path>` line each, plus `UI_LINKS_SKIPPED: <n>` for links on other hosts. Send each image with `SendUserFile`, `display: "render"`. Never open one with Read. When it finds none, or there is no PR, print one line: `The UI changes, but the PR has no screenshots.` or `The UI changes. There is no PR yet — screenshots in the PR description show up here.` With `UI_LINKS_SKIPPED` above 0, add `<n> more images link to other hosts; open the PR to see them.`
- **Alternatives the author named.** When `pr-context/body.md` names alternatives the author considered, or (on your own branch) this session discussed alternatives, you may add one line under the summary: `The author also considered: <…>.` Label it as the author's. It is for the human only.
- **The PR title line.** When the SUMMARY and the PR title disagree about what the change does, print `⚠ The PR title says <x>; the change does <y>.` State both; do not editorialize. On a re-review, never print it: the title describes the whole PR and the brief only the delta.
- **On a re-review** the first line ends `(what changed since the last review of PR #<n>)`.

#### 4.8c: High tier — stop for the user's go

Skip the stop in two cases, and say which in one line:

- `ARCH_APPROVED: 1` (`--understood`) → record `ARCH_GATE='approved'`, print `Not waiting for approval (--understood). Running the code review.`, go to Step 5.
- A re-review where `DELTA_PRIOR_ARCH_GATE: approved` and no part is marked `new` → record `ARCH_GATE='carried'`, print `You approved this architecture at the last review, and the delta adds nothing new. Running the code review.`, go to Step 5.

Otherwise record that the run waits, so an interrupted run can be resumed:

```bash
echo "ARCH_GATE='pending'" >> "$RUN_DIR/state.env"
```

Then end the brief with this and **end your turn**:

```
This changes the architecture across a boundary. Say "go" to run the code review,
or tell me what you would change in the design.
```

On your own branch, add `Don't edit files until the review is done.` — the checkpoint commit stays in place while the run waits.

> **HARD STOP.** Do not launch any subagent, Codex command, or Step 5 work before the user answers. Step 5's first action is `fr-arch-gate.sh`, which stays `closed` while `ARCH_GATE` is `pending`.

When the user replies, handle it by what it is:

- **Go** ("go", "yes", "ok", "approved", "looks right", "continue") → record `ARCH_GATE='approved'` and go to Step 5 in the same turn. Here a plain yes is enough: this is an approval, not a quiz.
- **A question about the change** → answer it in a few sentences, in domain words. Use Pass U's report (`raw/architecture.md`) and, when you need to, open the one source file from `SOURCE_ROOT` that settles it — never the whole patch. Then repeat the go line.
- **An objection to the design** ("this should live in Billing", "I don't want a second store") → record `ARCH_GATE='rejected'`, and do not run the code review: reviewing code the architect wants rebuilt wastes the run. Restate the objection in one or two sentences and confirm you got it right. The verdict is `DO-NOT-COMMIT` on your own branch and `REQUEST-CHANGES` in pr-remote, with the objection as its one blocker. Then run Steps 9 and 10 (no Step 8.6 handoff, no review record). On your own branch, offer to rework the design with the user's objection as the brief.
- **Stop words** ("stop", "cancel", "never mind") → run Step 9 to restore the tree, write no log entry, and say how to continue: re-run the review, or add `--understood` to skip the stop.

If the session ends while the run waits, restore first on the next turn (`fr-restore.sh "$RUN_DIR"`), then offer to re-run.

### Step 5: Fan out all reviewers (one parallel batch)

Runs only after Step 4.8 cleared. **Check it first, before launching anything:**

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-arch-gate.sh" "$RUN_DIR"
```

`ARCH_GATE: open` → launch the fan-out below. `ARCH_GATE: closed` → **launch nothing.** `REASON` is `pending` (the user has not answered — go back to 4.8c), `rejected` (the user objected to the design), or `not_decided` (Step 4.8 did not finish). There is no override.

**Subagent models.** Every subagent runs on a model chosen by pass, not on the session's model. `fr-preflight.sh` printed them as `SUBAGENT_MODELS` and wrote them to `state.env` as `MODEL_<pass>`. Set `model` on each Agent call to the pass's value — `MODEL_U` (architecture), `MODEL_I` (implementation), `MODEL_B` (cso), `MODEL_A` (lattice), `MODEL_W` (static-analysis), `MODEL_F` (fix check), `MODEL_R` (review army), `MODEL_X` (Codex compactor). The value `inherit` means: leave `model` off. The table lives in `scripts/fr-models.sh`; one pass can be overridden for a run with `FR_MODEL_<pass>`. Pass C is a Codex process and has its own model setting. A re-spawn uses the same model as the first launch.

Launch the Claude subagents **in a single message**:

| Pass | When |
|---|---|
| I — implementation | always |
| B — cso | always (`HAS_GSTACK: 1`) |
| A — lattice | `LATTICE_CONTEXT: yes` |
| R — review army | pr-remote, `ARMY_REQUESTED: 1`, `HAS_GSTACK: 1` |
| W — static-analysis | `SA_PRESENT: 1` |
| F — fix check | `DELTA: applied` and `DELTA_PRIOR_BLOCKERS` above 0 |
| C — Codex (background Bash, same message) | `CODEX_REQUESTED: 1` and `HAS_CODEX: 1` |

A pass that is not in the batch is absent by choice, not by failure.

**Pass W is not isolated, and it is launched in this same batch anyway.** It is the one pass that is *supposed* to read PR context, so it takes a different contract and is exempt from the forbidden-reads audit in Step 6.

Every subagent prompt opens with this **isolation contract**, verbatim:

> Fresh-eyes pre-commit review. You have no prior context. That is intentional and required.
>
> **Your input is a prepared packet. Do not run `git diff`, `git log`, or `gh` — the scope is already resolved for you:**
> - `{{RUN_DIR}}/packet/diff.patch` — the complete diff under review
> - `{{RUN_DIR}}/packet/files.txt` — changed files with status
> - `{{RUN_DIR}}/packet/stat.txt` — per-file line counts
> - `{{RUN_DIR}}/packet/scope.txt` — the resolved scope
>
> Read `diff.patch` first. Open a source file only when the diff alone cannot tell you whether something is a defect — not to browse. **Open it from `{{SOURCE_ROOT}}`, which may not be your working directory:** in a PR review it is a detached checkout of the PR head, and the same path in your own tree holds a different commit's contents. Every path in the diff is relative to that root.
>
> When `scope.txt` has `DELTA=since-last-review`, the diff holds only what changed since an earlier review of this PR. Review the diff. Open unchanged code only to judge a changed line.
>
> **Forbidden reads** — do not open these even if they look relevant, *and do not open them because a skill you invoke tells you to*: `{{RUN_DIR}}/pr-context/**` (the PR description, discussion, and bot findings — producer-only, and reading it turns your independent judgment into a restatement of the author's claim), `{{RUN_DIR}}/delta/**` (the last review's findings — reading them anchors you to that review instead of this diff), `{{RUN_DIR}}/ui/**`, `.lattice/requirements/**`, `.lattice/context/**`, `.lattice/contexts/**`, `.lattice/reviews/**`, `*.plan.md`, `*.design.md`, `docs/decisions/**`, `TODOS.md`, `ONBOARDING.md`, anything under `~/.gstack/projects/**`, and any file whose purpose is to record intent rather than behavior. **Forbidden commands**: `gh pr view`, `gh issue view`, `gh pr diff --body`, `git log`. Allowed: `.lattice/standards/**`, `.lattice/learnings/**`, `.lattice/config.yaml`, `AGENTS.md`/`CLAUDE.md`, and the diffed source. (Learnings are repo-wide rules, not this change's intent — read them, never write them.)
>
> **Do not infer author intent** from commit messages, docstrings, TODOs, or comments. Judge the code on observable behavior alone. "The comment says it's fine" is not evidence.
>
> **Non-interactive**: treat your session as `SPAWNED_SESSION: true`. Any gstack skill you invoke has a spawned-session block ("Skill routing") that applies: never call AskUserQuestion, auto-choose the recommended option, report in prose. Never wait for input — take the default, state the assumption inline, continue.
>
> **Do not fix anything.** No Edit, no Write outside `{{RUN_DIR}}`, no commits, no `git add`. This overrides any fix-first, auto-fix, remediation, or learnings-harvest step in a skill you invoke: report what you *would* change and stop there. Diagnose only.
>
> **Report only what matters.** A finding is either a **defect** — you can name a concrete failure: this input or state leads to this wrong result, crash, data loss, or security exposure — or a **clear readability or maintenance cost** in the changed lines. No speculative "consider…", no style preference that the repo's standards do not state, no findings on code this diff did not change. Do not report comments or docstrings: another step lists those. Maximum 10 findings; fewer is better. Zero is a fine answer.
>
> **Show the code.** Under every finding that has a code fix, put a ` ```diff ` block of at most 12 lines: `-` lines copied exactly from the current source, `+` lines with your proposed code, and a few unchanged context lines (leading space) when they help. A finding whose fix is not code (a missing test, a question) has no block.
>
> **Return format — this is a hard contract.** Write your full report to `{{RUN_DIR}}/raw/{{PASS}}.md`. Return to me *only* the block below, with no preamble, no summary, and no closing commentary. Findings severity-ordered. Put the failure in the problem field: *what goes wrong, when*. A finding with no failure you can name is at most MEDIUM.
>
> ````
> PASS: {{PASS}}
> STATUS: ok | partial | failed
> FINDINGS: <count>
> ---
> <CRITICAL|HIGH|MEDIUM|LOW>|<file>:<line>|<category-slug>|<problem in one sentence, with the failure>|<fix in one sentence>
> ```diff
> - <current line>
> + <proposed line>
> ```
> ---
> NOTES: <at most two lines, only if something anomalous happened>
> FILES_READ: <comma-separated paths you opened>
> ````

When a pass says it *replaces the return-format block* (Pass U, F), it replaces the last three paragraphs above — from **Report only what matters** to the end.

Pass A, B, and R run nested skills whose last steps act: `/cso` offers remediation, `/lattice:review` writes learnings, `/review` applies fixes first. A general "read-only" line does not reliably beat a nested skill's own steps, so each pass below names the sub-steps to skip by their heading, and Step 6.5 checks the result. Use `SPAWNED_SESSION: true` for non-interactive runs. **Do not set `GSTACK_HEADLESS`**: it makes gstack block on its first question instead of taking the default.

Then append the pass-specific task:

**Pass I — implementation** (every mode; no nested skill, this is a direct reading task)

> Review the implementation of this change: whether it does what it does correctly and readably. Read `diff.patch`, and open a source file from `{{SOURCE_ROOT}}` when you need a caller, a callee, or a type to judge a changed line.
>
> Look for, in this order:
>
> 1. **Correctness** — wrong logic, off-by-one, a missed case, wrong error handling, a race, a resource leak, a broken invariant. Trace at least one real caller of each changed public function.
> 2. **Contracts** — a changed API, event, schema, file format, or CLI that existing callers or data no longer fit.
> 3. **Data and migrations** — a migration that is not reversible, a backfill that locks or loses data, a default that changes stored meaning.
> 4. **Performance** — a query in a loop, an unbounded read, a hot path that got slower by a large factor. Not micro-tuning.
> 5. **Readability** — a name that says the wrong thing, a function doing two jobs, dead code, a copy of logic that already exists in the repo (name where). Only in the changed lines, and only when the cost is clear.
>
> Security is Pass B's; leave it unless it is also a plain correctness bug.

**Pass A — lattice** (`{{LATTICE_REVIEW_CMD}}`; only when `LATTICE_CONTEXT: yes`)
> Run `{{LATTICE_REVIEW_CMD}}` against the packet, in its default **summary mode**. Apply atoms conditionally: clean-code always; architecture, DDD, secure-coding, test-quality only when the delta touches their domain.
> **Stop after its "Step 4: Produce Report". Do not run "Step 5: Harvest Learnings and Log Review."** That step asks the user to confirm learnings and then writes them to a tracked file, which would inject a change into the diff under review *and* block on a question no human is there to answer.
> Map its `critical` findings to HIGH, `warning` to MEDIUM, and `suggestion` to LOW. Drop suggestions that only restate a checklist item with no cost in this code.

**Pass B — cso** (`{{CSO_CMD}}`, plus `--comprehensive` when `RISK: high`)
> Run `{{CSO_CMD}}`. Honor its confidence gate — do not report below it. Cover OWASP/STRIDE on the changed surface, secrets, dependency and CI/CD exposure introduced by this diff. Give each finding a concrete exploit path in the problem field. If nothing clears the gate, return `FINDINGS: 0` — do not pad.
> **Run through "Phase 12: False Positive Filtering + Active Verification", then report and stop.** From "Phase 13: Findings Report + Trend Tracking + Remediation", produce the findings report only — no remediation planning, no remediation questions, no patches.

**Pass R, W, F** — when one of them is in the batch, read its contract before you launch, and launch it in the same message as the others:

- Pass R (review army, pr-remote with `--army`) → `$FR_REFS/pass-r-army.md`. With `--army` and `HAS_GSTACK: 0` it cannot run: name it in the Step 8 reduced-coverage line.
- Pass W (static analysis, `SA_PRESENT: 1`) → `$FR_REFS/pass-w-static-analysis.md`
- Pass F (fix check, re-review) → in `$FR_REFS/delta.md`, already read at Step 1.6

**Pass C — Codex** (background Bash, launched in the same message, not a subagent) — **only when `CODEX_REQUESTED: 1` and `HAS_CODEX: 1`.** Read `$FR_REFS/codex.md` before the launch message, then launch Pass C in that same message.

### Step 6: Join and isolation audit

**If `CODEX_REQUESTED: 1`, join Codex first** by the rules in `$FR_REFS/codex.md`. Otherwise go straight to the isolation audit.

Check each `FILES_READ:` line against the forbidden list — **for the isolated passes only (I, A, B, R, F)**. Pass F may read `delta/prior-blockers.md`; for every other pass a `delta/` path is a leak. Pass U was already audited at Step 4.8; carry that result into the report. **Pass W is exempt:** reading `pr-context/**` is its assigned job. Any *other* pass with a `pr-context/` path is a serious leak.

- Clean → proceed.
- Forbidden path present → note the leak, downgrade that pass's confidence (its *"by design"* concessions become suspect; its bug findings do not). Re-spawn only if the leak is material and the pass is cheap.
- `FILES_READ:` missing → unverified isolation. Note it, proceed.

Self-reporting is the only audit available for *reads*. Treat it as a smoke detector, not a guarantee.

### Step 6.5: Reviewer mutation check (read-only enforcement)

The prompt asked the reviewers not to write. This verifies it, because a subagent inherits the parent's tool access.

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-mutation-check.sh" "$RUN_DIR"
```

`LEAK: none` → proceed. `LEAK: detected` → re-run with `--revert` to quarantine and restore:

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-mutation-check.sh" "$RUN_DIR" --revert
```

The script picks its own baseline from `CHECKPOINT`:

- `committed` and `skipped` both leave a clean tree at fan-out, so *any* dirt now came from a reviewer. Revert is safe.
- `failed` has the producer's own uncommitted work interleaved with the reviewer's. The script **refuses `--revert`** there (`REVERT: refused_checkpoint_failed`). Print the delta, name the suspect paths, hand it to the user.
- `pr_remote` is a baseline diff, and `--revert` is refused (`REVERT: refused_pr_remote`) for the same reason.

In pr-remote mode `PR_WT_LEAK` reports the PR worktree separately. Dirt there counts as a leak even though Step 9 deletes the worktree regardless.

**Untracked files are only listed, never cleaned.** Report `UNTRACKED_REMAINING` and let the user decide.

Record any violation, and treat that pass's findings as still valid but its judgment as suspect.

### Step 7: Triage

You are back in the producer context with full knowledge of design intent. Work from the compact blocks. **Pass W's is among them**, tagged `static-analysis`, under the static-analysis floor below. **So is Pass F's**, tagged `fix-check`, on a re-review, under the prior-blocker floor. Pass U's is not: it sets the tier, it does not find defects. The comment list from Step 4.4 is not triaged either.

**When `PR_CONTEXT: present`, read the PR context now.** Read `$RUN_DIR/pr-context/body.md` always, and `$RUN_DIR/pr-context/discussion.md` to check surviving findings against what the PR already settled (skim it when `DISCUSSION_LINES` is large). Use it two ways, and only these two:

- **Do not re-raise what the thread already resolved.** A finding a maintainer explicitly dismissed, or that a later comment shows was fixed, moves to NOISE (or BY DESIGN) **with a one-line citation of the specific comment** — never dropped silently.
- **A bucket-2 "by design" may cite a decision made in the discussion.** "The author presumably meant to" still is not a citation.

This never touches the security or static-analysis floors below.

Deduplicate across passes (same `file:line` + same root cause = one finding, sources merged, keep the clearest ` ```diff ` block), then assign each to exactly one bucket:

1. **BLOCKER** — a real defect with a failure you can state: *this input or state → this wrong result, crash, data loss, or exposure*. You checked that the failure holds — you read the code path, not only the reviewer's sentence.
5. **SHOULD FIX** — real, and worth fixing, but no failure: a readability or maintenance cost in the changed lines, a missing test, a copy of existing logic. It does not block.
2. **REAL BUT BY DESIGN** — cite the specific decision from this session, or the specific standard/doc, that makes it intentional. No citation → it goes back to bucket 1 or 5 on its merits.
3. **STYLISTIC / NOISE** — one sentence on why it doesn't matter here.
4. **REVIEWER MISUNDERSTOOD** — what they got wrong. Use sparingly; bias hard against this bucket.

(The numbers are the `findings.tsv` codes. Bucket 1 must stay "blocker", because a later re-review reads its blockers from that column.)

**The blocker bar is the loop breaker.** A finding with no failure you can state is **not** a blocker, whatever its severity. Do not promote a finding to bucket 1 "to be safe": a blocker costs a full fix-and-re-review cycle. **On a re-review**, a new finding is a blocker only when the delta caused it; a problem in code the last review already saw goes to bucket 5 at most, with `pre-existing` in its line.

Four overrides:

- **Security floor**: a `cso` finding at HIGH or CRITICAL cannot go to bucket 3, 4, or 5 without naming the specific compensating control and where it lives. Absent that, it is a BLOCKER.
- **Static-analysis floor**: a Pass W `UNADDRESSED` finding is a BLOCKER unless you can name the specific handling Pass W missed, cited by location.
- **Prior-blocker floor** (re-review only): a Pass F OPEN line is a BLOCKER. It leaves bucket 1 in only three ways, each cited: the specific change, by `file:line`, that fixed it and Pass F missed; a maintainer's dismissal in `pr-context/discussion.md`, quoted; or proof that the earlier finding was a misread, which requires that you opened the file. A blocker that leaves this way is `released` — say which of the three in `report.md` and count it in the log.
- **Convergence**: a finding raised by two or more passes cannot go to bucket 3. `codex` + any Claude pass is the strongest agreement; `review` + another Claude pass is moderate-to-strong; two Claude passes with different checklists are moderate. Do not manufacture agreement that no pass produced.

**In pr-remote mode there is no producer context:**

- **Bucket 2 may not cite a session decision.** It admits only a standard, a config, a code path you can point at in `SOURCE_ROOT`, or a decision recorded in the PR discussion, quoted.
- **Bucket 4 requires that you opened the file.**
- **The verdict vocabulary is `APPROVE` / `APPROVE-WITH-COMMENTS` / `REQUEST-CHANGES`.**
- Findings are **asks, not fixes.** Never edit the PR's code.

**The verdict** follows the buckets: bucket 1 non-empty → `DO-NOT-COMMIT` (pr-remote: `REQUEST-CHANGES`); otherwise bucket 5 non-empty, or comments to drop → `COMMIT-WITH-FIXES` (pr-remote: `APPROVE-WITH-COMMENTS`); otherwise `COMMIT` (pr-remote: `APPROVE`).

Write the triaged findings to `$RUN_DIR/findings.tsv` for the log: tab-separated, with the header `bucket	severity	location	sources	finding`, one row per finding. Keep this shape: a later re-review reads its blockers (the bucket-1 rows) from this file.

For each blocker and should-fix finding, also write one **plain sentence** for chat: what goes wrong, for whom or for what, and when — in domain words, with no function, variable, or file names. "A retried payment can charge the customer twice when the provider is slow." not "`charge()` lacks an idempotency key." Keep the pass's own wording in `findings.tsv` and `report.md`; the plain sentence is for the architect only.

### Step 8: Report to chat

**This is the primary output.** The brief was already shown at Step 4.8; do not print it again. Write the review as a normal chat reply: a short verdict sentence, then bullets with a bold label, in full short sentences. The fence below only shows the shape — do not print it:

````text
**<COMMIT | COMMIT-WITH-FIXES | DO-NOT-COMMIT; pr-remote: APPROVE | APPROVE-WITH-COMMENTS | REQUEST-CHANGES>.** <one sentence: how many blockers and should-fix findings>

- **Scope:** <branch, or PR #<n> at <short sha>>, <N> files, +<a>/−<b>. Risk: <low|medium|high>. Took <elapsed>.
- **Architecture:** <no change, reviewed automatically | brief shown | approved by you | carried from the last review | approval skipped (--understood) | tier unknown>.
- **Passes:** <implementation, cso[, lattice][, codex][, review][, static-analysis][, fix-check]>.
- **Re-review:** only the changes since <short PRIOR_HEAD> (last verdict <PRIOR_VERDICT>). Earlier blockers: <total> — <fixed> fixed, <open> still open.   (only when DELTA: applied)
- **Static analysis (<tool>):** <total> raised — <fixed> fixed, <suppressed> suppressed, <dismissed> dismissed, <unaddressed> unaddressed.   (only when Pass W ran)
- **⚠ Reduced coverage:** <what was missing>.   (only when a pass failed / was unavailable)

**Blockers (<n>)**

1. <The plain sentence.> ([<file>:<line>](<link>), <sources>)

**Should fix (<n>)**

1. <The plain sentence.> ([<file>:<line>](<link>))

**By design (<n>)**

- <The finding in one plain sentence> — by design because <the decision or standard>. ([<file>:<line>](<link>))

<n> comments and docstrings added by the change should go. Set aside <n> noise and <n> misread findings. The code for every finding is in [report.md](<RUN_DIR>/report.md).

<the closing line>
````

Rules:

- **No code blocks in the review.** No ` ```diff `, no code names. The diffs, the comment list, and the noise and misread findings live in `report.md`. Name a code thing only when there is no domain word for it, and then in inline backticks.
- **The location is a link at the end of the line**, not the subject of the sentence. Link to the file relative to the working directory, with `:<line>` in the target. In pr-remote link to its absolute path under `SOURCE_ROOT`.
- The verdict is the first line. Never bury it under a preamble.
- **The Risk** on the Scope bullet is Pass U's tier. When Pass U failed, write `unknown` and add the mechanical `RISK` in brackets.
- **The closing line.** On your own branch, when there are blockers, should-fix findings, or comments to drop: `Want me to fix the <n> blockers and <n> should-fix findings, and drop the added comments?` In pr-remote: `These are asks for the author. Nothing was posted to the PR.` On a clean `COMMIT` / `APPROVE`, no closing line.
- For a stack unit the **Scope** bullet names every PR in it and the unit: `PRs #42–#43 at <short sha>, stack unit 1 of 3`. **The last line of the whole chat output is the stack report** from the handoff: `STACK REPORT — <stack id> · unit 1/3 · PRs #42, #43 · REQUEST-CHANGES · blockers 2`. Print it exactly in that shape. When the run stopped at a high-tier approval, the verdict there is `ARCH-PENDING`.
- In pr-remote mode the **Scope** bullet names `PR_HEAD`. Add `⚠ The PR was updated during this review.` on `HEAD_DRIFT: yes`, and `⚠ The PR is MERGED` (or `CLOSED`) when it is not open.
- **The Re-review bullet prints only when `DELTA: applied`.** Its `<open>` count is the number of `fix-check` lines still in Blockers after triage; a released one counts as fixed.
- **The ⚠ Reduced coverage bullet prints only when the run lost a lens** — a pass that should have run failed, `HAS_GSTACK: 0`, a requested or required Codex could not run, `--army` was asked for and Pass R could not run, Pass F failed (`earlier blockers not checked`), Pass U failed (`risk tier unknown`), or the user accepted a delta after a reduced or pruned last review. On a required Codex that did not run, say it plainly: `Codex is required for high-risk changes and did not run (<reason>). Run codex login, then re-run.`
- A section with zero findings is omitted. Blockers is never omitted: with none, the verdict sentence says `No blockers.`

**When the run stopped at a high tier** (the user has not answered and the session ended): say `**Waiting for your go.** The code was not reviewed. Re-run the review, or add --understood to skip the stop.`

**When the user rejected the design** (4.8c): the verdict line is `**DO-NOT-COMMIT.** The architecture was not approved; the code was not reviewed.` (pr-remote: `**REQUEST-CHANGES.**`), then the objection as the one blocker, then the closing line from 4.8c.

### Step 8.5: Codex addendum (only when Codex landed late)

Only when Codex was launched with `CODEX_REASON: asked` and finished after Step 8 printed. Follow Step 8.5 in `$FR_REFS/codex.md`.

### Step 8.6: Hand the run to `/ship`

**Skip this step when the code was not reviewed** (`ARCH_GATE` is `pending` or `rejected`): say `SHIP_GATE: n/a — implementation not reviewed`.

**Skip this step entirely in pr-remote mode.** Say `SHIP_GATE: n/a — reviewed PR #<n>, not this branch`.

**Run before Step 9** — it needs the checkpoint SHA, which the reset destroys.

Build the pass list from the passes that actually ran and returned `STATUS: ok`. Start from `implementation,cso`, add `lattice` only when Pass A ran (dropping any that failed), and append `,codex` **only** when Codex was requested *and* returned `STATUS: ok`. Then:

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-handoff.sh" \
  "$RUN_DIR" "$STATUS" "$VERDICT" "$FR_PASSES" "$RUN_DIR/findings.json"
```

- `STATUS` is `clean` only when bucket 1 is empty; otherwise `issues_found`.
- The fourth argument is the comma list of **critic** passes that returned `STATUS: ok`. Never include `codex` when it did not run, and never include `architecture`, `static-analysis`, or `fix-check`. The ship-side gate cuts ship's `testing`/`maintainability` specialists only if `lattice` is listed, and ship's Codex passes only if `codex` is — listing a pass that did not run silently removes coverage from the final gate.
- `findings.json` is a JSON array you write first: **only buckets 2, 3, and 4**, each as `action: "skipped"`. **Never log a bucket 1 finding** — ship re-reviews it, which is the regression check on your fix. `fingerprint` is exactly `path:line:category`.

**When the handoff fails** — `SHIP_GATE: will_not_fire` — say so in chat: ship will re-dispatch its full Step 9 army and re-ask about findings you already triaged. Continue either way.

### Step 9: Restore working state

Regardless of verdict:

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-restore.sh" "$RUN_DIR"
```

Three independent undos, each separately gated:

- `RESET` drops the checkpoint commit — **only** when it actually landed, and only when HEAD still *is* the checkpoint.
- `INDEX` restores the pre-review index with `git read-tree`, in exactly the two states where `git add -A` ran: `committed` and **`failed`**.
- `WORKTREE` removes the pr-remote checkout and deletes the temporary `refs/fresh-review/pr-<n>` ref.

Everything is skipped when `CHECKPOINT=skipped`.

Then tell the user: "Working tree restored — staged/unstaged split is back as it was." In pr-remote mode say instead: "Your tree was never touched; the PR checkout has been removed."

This must run even on abort or error. If the user interrupts mid-review, restoring the tree is the first thing you do on the next turn — `fr-restore.sh "$RUN_DIR"` is all it takes.

### Step 10: Persist the run log

**In pr-remote, record the review first:** follow "At Step 10: record the review" in `$FR_REFS/pr-remote.md`.

Write `$RUN_DIR/report.md` — the **long form**, for the session that fixes the findings: the Step 8 chat output; the brief (tier, reason, summary, parts, links to the diagram PNGs and Excalidraw files, the UI images line); the user's answer at a high tier; then **every blocker and should-fix finding with its pass wording and its ` ```diff ` block** (when a pass gave no block and the fix is code, open the file from `SOURCE_ROOT` at that line and print the current lines as `-` lines); the full comment list from `packet/comments.tsv` (one bullet per file, line ranges, `docstring (<k> lines)`); the NOISE and MISREAD findings in full; the by-design citations; `VOCAB`; the lattice line; the PR-context and static-analysis summary; the scope; and the isolation-audit result. Then read `$FR_REFS/run-log.md`, and write `$RUN_DIR/run.json` and append it to the index as it says.

## Failure modes and recovery

- **Checkpoint commit fails** (`CHECKPOINT: failed`) → no-checkpoint mode (Step 3), document it, and **still run `fr-restore.sh`**.
- **Unmerged index** (`STOP_REASON: unmerged_index`) → stop at preflight. Resolve the conflict, then re-run.
- **A pass returns nothing / errors** → log it as skipped, drop it from the `passes` list in Step 8.6, and continue. The verdict names the absent lens.
- **A pass ignores the compact return contract** and dumps prose → do not re-read it; extract findings from its `raw/` file with a compactor subagent.
- **Codex times out / fails** → verdict ships Claude-only, the `codex` pass kept with `"status":"failed"`. Never substitute a Claude pass for it.
- **Required Codex cannot run** (`RISK: high` or tier `high`, and `HAS_CODEX: 0` or Codex failed) → a named gap: print the reduced-coverage line (Step 8).
- **Subagent tries to fix code** → Step 6.5 catches it; `--revert` undoes it unless the checkpoint failed.
- **User aborts midway** → `fr-restore.sh "$RUN_DIR"` first, then report what was collected.
- **Forbidden read detected** → Step 6 handles it. A Pass U leak: re-spawn it, or label the brief `[intent-contaminated]`.
- **`runs.jsonl` fails to validate** → the line is dropped, `$RUN_DIR/run.json` is kept, tell the user.
- **Handoff fails** (`SHIP_GATE: will_not_fire`) → continue, and say ship will re-dispatch its full army.
- **Pass U fails** → do not block. Print `⚠ Risk tier unknown`, go to Step 5, name it in the reduced-coverage line, log `architecture.gate: failed`.
- **Pass U puts code names in the diagrams or the summary** (a class, a function, a file, a table) → re-spawn it once with the "domain words only" rule repeated. On a second failure, show what it returned and note it.
- **Pass U sets `low` but its PARTS list added or removed parts** → treat the tier as `medium` and show the brief. The tier rule says the worst item decides.
- **A diagram does not render** (`DIAGRAM_<x>: failed`, most often invalid Mermaid) → print its fence as 4.8b says. Do not hand-fix it.
- **Excalidraw cannot render** (no gstack bundle, no `bun`, no browser) → `fr-diagrams.sh` falls back to `mmdc` on its own. Say once that the diagrams are Mermaid PNGs.
- **PR images fail to download** (`UI_IMAGES: 0` with `UI_FETCH_FAILED` above 0) → print `The UI changes; the PR's screenshots could not be downloaded — open the PR to see them.` and go on.
- **`fr-comments.sh` lists a line that is not a comment** → drop it from the list and note it in `report.md`.

## What this skill does NOT do

- **Run the app, in any mode.** Launching a review tree runs code that may be untrusted with your credentials, and whether a tree is your own cannot be decided from git. UI screenshots come from the PR only.
- **Ask the user to judge code.** The user reviews architecture. Code findings are triaged here and fixed by the calling session.
- **Open a literal fresh Claude Code session.** For maximum isolation before a major release: `git worktree add ../review-wt HEAD`, start Claude Code there, run the commands manually.
- **Auto-apply fixes.** The calling session applies fixes after triage, on the user's yes. This skill only diagnoses.
- **Replace a full security audit.** `/cso --diff` covers the changed surface only.
- **Replace QA or run the CI gates.** A `COMMIT` verdict says the code reads correctly, not that it passes.
- **Stop `/ship` from reviewing again.** Ship's pre-landing review reviews the *final* diff. `references/ship-dispatch-gate.md` trims the parts that are genuinely duplicated.
- **Post anything to GitHub.** No `gh pr comment`, `gh pr review`, or `gh pr edit`, in any mode. Reading the PR (Step 4.7) and downloading its screenshots (Step 4.8b) is read-only.
- **Feed PR context to the isolated passes.** `pr-context/` reaches only triage, the brief's screenshots, and Pass W.
- **Re-review your own branch as a delta.** `--delta` works for pr-remote and stack units only.
- **Modify the PR under review.** pr-remote mode is read-only on someone else's branch.
- **Review a PR from another repo.** `foreign_repo` stops it. Clone that repo and run there.
- **Run gstack's `/review` by default**, or **lattice on a change with no lattice context.**
- **Remove comments itself.** It counts them; the calling session drops them.

## Examples

**"fresh review my changes before I commit"** on a branch that fixes an off-by-one in invoice totals → Pass U: `TIER: low` — no part or link changes. Chat: `**Risk: low.** No architecture change — the fix stays inside invoice totals. Running the code review.` Pass I and `/cso` run. Chat: `**COMMIT-WITH-FIXES.** No blockers, one should-fix finding.` with one plain sentence, and the offer to fix it.

**"fresh review"** on a branch that adds a retry wrapper around the payment provider client → Pass U: `TIER: medium` — a new retry mechanism inside the Checkout context. The brief: BEFORE shows Checkout calling the Payment provider once; AFTER adds a `Retry policy` service between them, marked added. Summary: checkout no longer fails on the first provider timeout; the cost is that a charge can now be sent more than once, so the provider link must be safe to repeat. The code review runs in the same turn. Chat gets one blocker: `A retried payment can charge the customer twice when the provider is slow.`

**"review PR 42"** that moves refund records from Billing into a new Ledger context and publishes a `Refund issued` event → Pass U: `TIER: high`. The brief shows BEFORE (Billing owns refunds) and AFTER (Ledger owns them, Billing listens to the event), two paragraphs, and the two screenshots from the PR description because the refund page changed. Codex becomes a must. The run stops: `Say "go" to run the code review, or tell me what you would change in the design.` The user says "go"; Pass I, `/cso`, and Codex run; the findings are asks for the author.

**"review PR 42"**, and the user answers the brief with "refunds must stay in Billing" → `ARCH_GATE='rejected'`. No code review. `**REQUEST-CHANGES.** The architecture was not approved; the code was not reviewed.` with the objection as the one blocker.

**"fresh review, don't wait for me"** → `--understood`. A high tier shows its brief and goes on.

**"fresh review with codex"** → `--codex`. Same run plus Pass C in the background; Step 8.5 posts an addendum if it lands late.

**"re-review PR 42"** after fixes → `--pr 42 --delta`. Pass U sets the delta's tier: the fixes touch no parts, so `low`, and no stop. Pass F checks the earlier blockers.
