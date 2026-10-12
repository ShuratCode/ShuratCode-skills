---
name: fresh-review
description: |
  Understand-first, fresh-eyes code review. Every run starts by explaining the change at a high
  level, as if to someone new to the project: what this part of the system is, what the user sees or
  what the system now does differently, how it fits, a UML class diagram, a sequence diagram, a flow
  diagram with the decision points, and the alternatives. Then it checks, with an open question, that the user knows what the change is —
  not a yes/no approval, and not a hunt for bugs. Only after that does it review the
  implementation, via context-isolated subagents that cannot read design docs, intent, or prior
  session context: a fast implementation pass and the gstack security audit always, the lattice
  review only when the feature has a lattice design or context doc. Every finding prints the code it
  wants to change as a diff. It also lists every comment and docstring the change adds, to drop. A
  finding blocks only with a concrete failure scenario, so the review does not loop on nits. A
  cross-model Codex pass is off by default: it runs when the invocation asks for it ("with codex",
  "cross-model review", "codex pass"), and it is a must when the diff is high-risk. Triages findings
  against the producer-context, prints the verdict and findings to chat, and logs the run.

  Does NOT run gstack's `/review` army by default. On your own branch `/ship` runs it at Step 9. On
  someone else's PR it runs only with `--army` ("with the review army", "full army") — it is the
  slowest pass (about 15 minutes).

  Use when the user asks to "fresh review", "fresh-eyes review", "review my changes", "pre-commit
  review", "review before commit", "review with no bias", "independent review", "what did I miss",
  "check my work before I commit", "context-free review", "help me understand this change", or
  "review with fresh eyes". Proactively suggest before any /ship, /land-and-deploy, or manual git
  commit when the diff exceeds ~50 lines or touches auth, payments, migrations, or
  security-sensitive code.

  Has a second mode — **pr review** — that adds a low/med/high risk class and a one-line note when
  the change touches frontend UI. Use it when the user asks for a "pr review", "review this PR",
  "explain this PR", "what does this PR do", "what does this change do", "summarize this change/PR",
  "diagram this PR", "explain my changes in plain English", "write the PR description", or names a
  PR by number or URL ("review PR 42", "look at github.com/o/r/pull/42").

  Has a third mode — **stack** — for a stack of PRs. It reviews nothing itself. It maps the stack,
  decides which PRs are reviewed alone and which are combined, and prints one handoff prompt per
  review. The user runs each review in a new session and reports back; the orchestrator tracks the
  stack's progress and verdict. A stack of one PR is reviewed right away. Use it when the user asks
  to "review this stack", "review the stack for PR 42", "review PRs 41 42 43", "review my stacked
  PRs", or names two or more PRs to review.

  PR reviews and stack units also support a **re-review** (`--delta`): it reviews only what changed
  since the last review, and checks that each earlier blocker is fixed. Use it when the user asks to
  "re-review PR 42", "review PR 42 again", "review the fixes on PR 42", or "re-review unit 2".

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

Understand the change first, then review it with fresh eyes.

## Modes

Two output shapes, one machine. Every mode starts with the understanding gate (Pass U), then fans out the same implementation passes against the same packet. The implementation passes are Pass I (implementation) and `/cso` always, lattice when the feature has a lattice context doc, and Codex when asked for or when the diff is high-risk.

| The user's words | Preflight flags | Subject of the review | Chat output |
|---|---|---|---|
| "fresh review", "review before I commit", "what did I miss" | *(none)* | your branch | **the change explained** → check → verdict + findings |
| "pr review", "explain this PR", "what does this change do", "write the PR description" | `--mode pr` | your branch | same, plus a risk class |
| "review PR 42", a `github.com/…/pull/42` URL | `--pr 42` | PR 42's head commit | same, plus a risk class |
| "review this stack", "review the stack for PR 42", "review PRs 41 42 43" | `--stack "<refs>"` | nothing — this session only plans | **the plan** + **one handoff per review** |
| "re-review PR 42", "review PR 42 again", "review the fixes on PR 42" | `--pr 42 --delta` | only what changed on PR 42 since its last review | same as a PR review, on the delta |

Chat carries the explanation, the understanding check, the verdict, the blockers and should-fix findings with their code, the comments to drop, and one-line by-design entries. Everything else — the risk factors, the pass inventory, the noise and misread findings, the coverage notes — goes to `report.md`. Whenever the review subject has an associated PR, the run also gathers PR context (Step 4.7) and, if the PR carried static-analysis findings, verifies each was handled (Pass W).

Resolve the mode once, from the invocation, and pass it to `fr-preflight.sh`. Do not re-derive it later.

- **Explicit flags win.** When the request already carries `--pr`, `--since-pr`, or `--stack`, pass them through verbatim and do not re-read the numbers in it. A stack handoff starts with `--pr 43 --since-pr 42`: that is one pr-remote review, not a stack.
- The word **stack**, or **two or more** PR numbers or pull URLs, means `--stack "<the refs>"`. One ref with the word stack ("review the stack for PR 42") is enough: the script finds the rest of the stack.
- A **number or pull URL** anywhere in the request means `--pr <that>` — which implies `--mode pr`.
- **Re-review words** with a PR ref — "re-review", "review again", "review the fixes", "only what changed since the last review" — add `--delta`. With no PR ref there is nothing to re-review against: say that re-review works for PRs and stack units only, and run the normal review.
- Any plain-English *"what does this do"* framing means `--mode pr` with no PR ref.
- Everything else is the default. When in doubt, default.
- **`--army`** when the request asks for gstack's review army ("with the review army", "full army", "run /review too"). It only matters in pr-remote.
- **`--understood`** when the user says they already understand the change ("I know this change", "skip the understanding check"). It skips Step 4.8. `--arch-approved` is the old name and still works.
### The Codex opt-in, and the high-risk rule

**Codex (Pass C) is off by default. It runs when the invocation asks for it, and it is a must when the change is high-risk.** It is a separate `--codex` flag, orthogonal to `--mode` and `--pr` — add it to *any* of the three rows above. Resolve it once, from the invocation, alongside the mode:

- Pass `--codex` when the request names Codex or asks for cross-model coverage: "with codex", "codex pass", "cross-model review", "run codex too", "add a second model", "include the cross-model reviewer".
- Otherwise **omit it** — a plain "fresh review", "pr review", or "review PR 42" on a normal-risk diff gets the Claude passes (Pass I + `/cso`, plus lattice with a lattice context) and no Codex. Do not add `--codex` yourself: the high-risk rule below is mechanical and needs no flag.
- **High risk makes Codex a must.** When `fr-packet.sh` classifies `RISK: high` (Step 4), it sets `CODEX_REQUESTED=1` and `CODEX_REASON=risk` in `state.env` itself. In `pr` mode, a Pass K `RISK_LEVEL: high` on a mechanically normal diff does the same after the fan-out (Step 6). A required Codex has **no join budget**: the verdict waits for it. `CODEX_REASON` tells the two apart — `asked` (the user's flag), `risk` / `risk-pass` (forced), `none`.
- The flag is a request, not a guarantee: Pass C runs only when `CODEX_REQUESTED: 1` **and** `HAS_CODEX: 1`. If Codex was asked for or required but `codex` is not on PATH, say so — same as any other missing tool. On a high-risk run that is a loud gap, not a footnote (Step 8).

Everything downstream keys off `CODEX_REQUESTED` from `state.env`: Step 5 launches Pass C only when it is `1`, and the pass line, triage convergence, handoff, and log all treat an un-requested Codex as simply absent — distinct from a requested one that failed.

### The understanding gate

**Every mode explains the change before it reviews it.** Pass U reads the diff alone and writes a high-level explanation for a newcomer: the system in brief, what changes, how it fits, a class, a sequence, and a flow diagram, and the alternatives. The skill shows it, then asks one or two open questions about *what* the change is — never about bugs or edge cases. The implementation review starts only when the user's answer holds the key points. Step 4.8 has the full rules.

The gate skips only four ways: `--understood` at invocation, a trivial change (`CHANGE_KIND: trivial`), a re-review whose delta has no new parts after the user understood the last review, or an explicit waiver from the user ("skip the check"; recorded `waived`).

This is one of two places the skill stops for an answer; the other is a re-review whose delta needs the user's choice (Step 1.6).

**`pr` mode adds one pass — K — plus a UI presence check.** Pass K (risk) classifies the whole change `low` / `med` / `high` by blast radius and reversibility, so the reader sees the stakes next to the verdict. Step 4.6 reports, in one line, whether the change touches frontend UI — it does **not** launch the app or take screenshots (launching a review tree is an RCE risk; see Step 4.6).

### pr-local and pr-remote

`--pr <ref>` moves the subject of the review off your branch, and several things follow from no longer being the author:

| | `review` / `pr` on your branch | `pr` with a ref (**pr-remote**) |
|---|---|---|
| What is reviewed | merge-base..worktree | the PR head, fetched fresh |
| Source files opened from | your checkout | a detached worktree at the PR head (`SOURCE_ROOT`) |
| WIP checkpoint (Step 3) | runs | **skipped** — nothing of yours is being reviewed |
| Verdict vocabulary | `COMMIT` / `COMMIT-WITH-FIXES` / `DO-NOT-COMMIT` | `APPROVE` / `APPROVE-WITH-COMMENTS` / `REQUEST-CHANGES` |
| Triage bucket 2 ("by design") | may cite this session's decisions | **may not** — you have no intent knowledge |
| Handoff to `/ship` (Step 8.6) | runs | **skipped** — you are not shipping this |
| gstack `/review` army (Pass R) | not run — `/ship` Step 9 owns it | **only with `--army`** — the slowest pass |

### Stack mode and re-review

- **Stack mode** (`--stack`) turns this session into an orchestrator. It reviews no code: it plans review units, prints one handoff per unit for the user to run in a new session, and tracks the `STACK REPORT` lines the user pastes back. A stack of one PR is reviewed here as a normal `--pr` run. The rules are in `$FR_REFS/stack.md`; Step 1 says when to read it.
- **Re-review** (`--delta`, pr-remote and stack units only) reviews only what changed since the last recorded review of the PR, and Pass F checks each earlier blocker. The rules are in `$FR_REFS/delta.md`; Step 1.6 says when to read it.

## Configuration

```
LATTICE_REVIEW_CMD="/lattice:review"     # Lattice standards conformance (plugin-namespaced)
CSO_CMD="/cso --diff"                    # gstack security audit, scoped to branch changes
CODEX_JOIN_BUDGET=240                    # seconds to wait for Codex after the Claude passes return
FR_RUN_RETENTION=20                      # run directories kept before pruning (env var, read by fr-log.sh)
DDD_DOC=".lattice/standards/ddd-principles.md"   # vocabulary for Pass U; resolved by fr-ddd-vocab.sh
FR_STACK_SMALL_LINES=80                  # stack mode: a PR this small joins the unit below it (env var)
FR_HANDOFF_CMD="/fresh-review:review"    # stack mode: the command each handoff starts with (env var)
```

- Review scope is resolved by `fr-preflight.sh`: `branch` (merge-base..worktree) when an `origin/<base>` exists, `working` otherwise, or `pr` (merge-base..PR head) when a PR ref was given.
- **Lattice (Pass A) runs only when the feature has a lattice design or context doc** (Step 4.4). It is the second slowest pass (median ~5 min).
- `/cso --diff` keeps the 8/10 confidence gate. High-risk diffs upgrade to `--diff --comprehensive` (Step 4).
- **The mechanical `RISK`** (`normal`/`high`, from `fr-packet.sh`) gates `/cso` depth and Codex in every mode. **Pass K's risk class** (`low`/`med`/`high`) is `pr` mode only.
- **Re-review records** live in `$LOG_DIR/reviews/`, next to `runs.jsonl`, and are never pruned.
- **PR context** (Step 4.7) is gathered whenever a PR exists, for triage and Pass W only, never for the isolated passes. It needs `gh`; with no PR or no `gh` it skips itself.

## gstack's `/review` is not a default pass

On your own branch `/ship` runs `/review` at its Step 9, so this skill never runs it there. On someone else's PR it runs only with `--army` (Pass R): it costs a median 15 minutes and about 30% of a run's tokens. The plugin's `references/ship-dispatch-gate.md` trims what ship would repeat after this skill.

## Output contract

Two audiences, two artifacts. Do not confuse them.

- **Chat is for the human, and it is kept lean.** First the explanation of the change and the understanding check (Step 4.8). After the review: the verdict on its own line, then the blockers and should-fix findings, **each with the code it wants to change as a `diff` block**, then the comments to drop, then one line per by-design finding. Noise and misread findings are counted in one line; their detail is in `report.md`. It is never a pointer to a file in place of the findings. Chat reads like a normal reply to a person: short sentences, bullets with bold labels, links. **Only code goes in a code block** (the `diff` blocks, a `mermaid` fallback, a stack handoff to copy). Every file reference is a link.
- **Disk carries the long form.** The full Pass U report, the risk rationale and factors, the pass inventory, the noise and misread findings, the UI-preview note, the coverage notes, raw pass reports, the diff packet, and the run log all live in the run directory (`report.md` and `raw/`).
- **Nothing is for GitHub.** No mode posts, comments, or edits a PR. See "What this skill does NOT do".

## Token discipline

Five invariants. Every step below is built around them; violating one silently makes the run cost several times what it should.

1. **The orchestrator never loads the diff** — nor the DDD principles document, nor the PR's own content beyond what triage needs. `fr-packet.sh` classifies risk with `grep -c` over the patch and prints only counts; `fr-ddd-vocab.sh` extracts the vocabulary sections into a brief and prints only its line count; `fr-pr-context.sh` writes the PR description and discussion to disk and prints only counts (`DISCUSSION_LINES` among them). The one producer-side read is triage's: `body.md` always, `discussion.md` bounded by its line count (skim when large). The static-analysis material is never read by the orchestrator at all — it is handed to Pass W by path.
2. **Reviewers read the packet, not git — and never the PR context.** The diff is materialized once (Step 4) and every isolated pass is handed the same file paths. No isolated pass re-derives scope, runs `git diff`, or opens `pr-context/`. Pass W is the sole exception on both counts: it reads `pr-context/` because verifying analyzer findings is its whole job, and it is not a critic.
3. **Passes return compact findings; prose goes to disk.** This is the largest saving by far. `/cso` alone emits thirteen numbered phases of narrative; the compact block is a few hundred tokens. Each pass writes its full report to `$RUN_DIR/raw/` and returns only the fixed-format block in Step 5.
4. **Raw reports are not read back.** Triage runs on the compact blocks. Open a raw report only to disambiguate one specific finding, and read only that finding's section.
5. **Nothing heavy enters the orchestrator by accident.** Never open a rendered PNG with Read — send it with `SendUserFile`, which does not put the image in your context; an image costs ~40k tokens. Never re-read this SKILL.md mid-run; it is already loaded. Past runs lost 370k tokens this way. The orchestrator makes ~40 calls per run, and everything in its context is paid again on every call.

The same principle governs the shell work: every mechanical step is a script in `${CLAUDE_PLUGIN_ROOT}/scripts/` that prints a small delimited key block. Read the block, not the machinery. Do not reimplement a script's logic inline — the scripts are where the gating rules are actually enforced, and a hand-typed variant of one is how those rules get lost.

## Workflow

Steps run in order. Step 5 is one parallel fan-out; everything else is sequential. In stack mode only Steps 0, 1, and **S** (in `stack.md`) run — Step S replaces the rest, except for a stack of one PR, which Step S turns back into a normal `--pr` run. Otherwise, steps are mode-conditional where their heading says so: **1.5** and **1.6** run in pr-remote, **4.6** (UI presence check) runs only in `pr` mode, **4.7** (PR context) runs in any mode when a PR is discoverable, **4.8** (understanding gate) runs in every mode unless `--understood` and waits for the user's answer before Step 5, **3** and **8.6** are skipped in pr-remote, and Step 5's fan-out grows with the run — Pass A when there is a lattice context, Pass K in `pr` mode, Pass R in pr-remote with `--army`, Pass W when the PR carried analyzer findings, Pass F on a re-review with earlier blockers, and Pass C when Codex is requested or required.

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
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh"                   # review mode
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh" --mode pr          # pr mode, your branch
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh" --pr 42            # pr-remote (implies --mode pr)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh" --codex            # review mode + Codex (Pass C)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh" --pr 42 --codex    # pr-remote + Codex
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh" --understood       # skip the understanding check (Step 4.8)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh" --pr 42 --army     # pr-remote + the gstack review army (Pass R)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh" --stack "42"       # stack mode: find the stack around PR 42
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh" --stack "41,42,43" # stack mode: exactly these PRs
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh" --pr 43 --since-pr 42  # one review of PRs 42..43 (a stack unit)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh" --pr 42 --delta     # re-review: only what changed since the last review
```

<!-- FR:BOOTSTRAP:START -->
Run this with the plugin root from Step 0 set in the same shell — prefix the command with `CLAUDE_PLUGIN_ROOT="<the path Step 0 resolved>"`, since this fresh shell does not carry it.
<!-- FR:BOOTSTRAP:END -->
This probes the repo, resolves the review scope, creates the run directory, and writes `state.env` — including the plugin root itself, so no later step has to resolve it again. Export `RUN_DIR` from its output — every later script takes it as `$1`. Pass the flags from the Modes table verbatim, add `--codex` only when the invocation asked for it (see "The Codex opt-in, and the high-risk rule" — high risk turns Codex on later, in Step 4, without the flag), add `--understood` only when the user said they already understand the change, and add `--army` only when they asked for the review army (see "Modes"); the script rejects an unknown flag or mode with a non-zero exit rather than falling back to a default, because a silently-defaulted `--pr` would review the local branch under someone else's PR number.

**In stack mode, read `$FR_REFS/stack.md` now and follow its Step S.** It replaces every other step (a stack of one PR comes back here as a `--pr` run).

On `STATUS: stop`, tell the user and stop. `STOP_REASON` is one of:

- `not_a_repo` — nothing to do here.
- `nothing_to_review` — no dirt and no commits the base branch lacks.
- `unmerged_index` — a conflict is in progress. Do **not** checkpoint a conflicted tree; a half-merged tree is not a reviewable diff. Resolve it, then re-run.

Neither of the last two can fire under `--pr`: both describe the local tree, which is not the subject of a pr-remote review.

Tool-availability accounting — state each of these up front, never silently:

- `HAS_GSTACK: 0` → `/cso` does not exist here. **A critic pass cannot run.** Say so plainly, run Pass I (plus Pass A and Pass C when they apply), label the verdict reduced-lens. Discovering this inside a subagent instead wastes the run and produces a report that looks complete but isn't. Note also that no gstack install means no `/ship` either, so the structural specialists this skill defers to will never run at all.
- `CODEX_REQUESTED: 0` → the run did not ask for Codex. Step 4 still turns it on when `RISK: high`; re-read `CODEX_REQUESTED` from the packet output there. If it stays `0`, Pass C does not run and is absent by choice, not by failure. This is the default. Do not mention missing cross-model coverage as a gap — it was not requested. Only note, once, that `--codex` is available if the user wants a second model.
- `CODEX_REQUESTED: 1` with `HAS_CODEX: 0` → Codex was asked for but `codex` is not on PATH, so Pass C **cannot** run. Say so plainly, run the Claude critics, label the verdict reduced-lens, and do not substitute a Claude pass for it. Fix is `codex login` (or installing the CLI) and re-run.
- `CODEX_REQUESTED: 1` with `HAS_CODEX: 1` → Pass C runs (Step 5).
- `HAS_GH: 0` → pr-remote is impossible. Only matters when a PR ref was given; Step 1.5 stops on it.
- `DELTA_REQUESTED: 1` → the user asked for a re-review. Step 1.6 decides whether a delta is possible. `--delta` without `--pr` is rejected with exit 2.
- `PLUGIN_VERSION` is the version of the running copy (also `FR_VERSION` in `state.env`, and `plugin_version` in the log). `PLUGIN_STALE: yes` means a newer version (`PLUGIN_INSTALLED`) is installed than the one this session loaded — the desktop app's per-session snapshot lags the install. Say once: `⚠ this session runs fresh-review <PLUGIN_VERSION>; <PLUGIN_INSTALLED> is installed. Start a new session to use it.` Then go on. It is not a stop: the running copy's scripts and instructions still match each other.
- `ARCH_APPROVED: 1` → the user already understands the change (`--understood`); Step 4.8 is skipped. `ARCH_APPROVED: 0` is the default and the check runs.
- `ARMY_REQUESTED: 1` → the user asked for gstack's review army. Pass R runs in pr-remote when `HAS_GSTACK: 1`. On your own branch it does nothing: `/ship` runs the army. `0` is the default; mention once, in pr-remote, that `--army` adds it (~15 min).
- `CODEX_CFG: unknown` → `gstack-config` was not found, so the setting could not be read. Report unknown, never guess `enabled`. This setting gates *gstack's* internal Codex, not ours; Pass C runs on `CODEX_REQUESTED` and `HAS_CODEX`, never on this.

Two other outputs matter later:

- `DIRTY: 0` with `AHEAD > 0` → the branch carries commits the base does not, pushed or not. Review them: the checkpoint self-skips in Step 3, scope stays `branch`. This is the normal shape of an open PR whose work is fully committed and pushed.
- `INDEX_TREE` is a real tree object written from the pre-review index, so it carries the staged *content* of every path, not just its name. Step 9 restores from it **exactly**. A name list cannot do this: a partially staged file — some hunks in the index, others not — restores by re-staging the whole file, silently folding the unstaged hunks in and destroying the split the user built.

The run directory persists, so a run can be analyzed afterward. It lives under `.fresh-review/` when that path is gitignored, and under the git dir otherwise; the script never edits `.gitignore`. `LOG_DIR` is the common git dir, so the run index survives worktree removal. An index entry may outlive its run directory.

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

`fr-preflight.sh` already printed `REVIEW_SCOPE` and `DIFF_CMD`. Say them out loud — one canonical scope string, handed identically to every reviewer so their findings are comparable. Nothing is materialized yet; the packet is built in Step 4, after the checkpoint, so that untracked files are in it.

State `SOURCE_ROOT` too whenever it is not the repo root. It is the one piece of scope a reviewer can get wrong silently: reading the right path in the wrong tree returns plausible file contents from the wrong commit.

### Step 3: WIP checkpoint

**Skip this step entirely in pr-remote mode** — `CHECKPOINT` is already `pr_remote`, the diff comes from two committed refs, and there is nothing of yours under review. Committing the user's unrelated work-in-progress in order to review someone else's PR would be a mutation with no purpose.

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-checkpoint.sh" "$RUN_DIR"
```

Commits everything with `--no-verify` (this skill IS the review), or self-skips when the tree is already clean. `CHECKPOINT` comes back as exactly one of `committed`, `skipped`, `failed` — never empty, because three later steps branch on it and an unset value fails *silently* rather than loudly. `CHECKPOINT_SHA` is always set.

**What the checkpoint is for:** making untracked files visible. A brand-new file does not appear in `git diff` at all, so without staging it the reviewers would never see the code most likely to contain fresh bugs. It also pins a stable SHA for the audit trail and for Codex's `--commit` scoping. It does not freeze what reviewers read — they read the packet, which is why the packet is built after this point and not before.

`CHECKPOINT` and `INDEX_TREE` stay distinct because the two undos in Step 9 are independent. `git add -A` mutates the index whether or not the commit that follows succeeds; a "no checkpoint, so skip the restore" rule would leave the user's carefully split index fully staged.

On `CHECKPOINT: failed`, continue in no-checkpoint mode: the packet builds from `git diff HEAD` / `git diff $DIFF_BASE`, untracked files go unreviewed (record that in the report), and the script has already written `raw/pre-fanout.status` as the baseline the Step 6.5 mutation check needs. **Step 9's index restore still runs** — only the commit-reset half is skipped.

**Do not edit anything from here until Step 9 completes.** A formatter-on-save or codegen watcher firing mid-review produces findings with stale line numbers.

### Step 4: Build the shared diff packet and classify risk

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-packet.sh" "$RUN_DIR"
```

Materializes the scope **once** into `$RUN_DIR/packet/` — `diff.patch`, `stat.txt`, `files.txt`, `scope.txt` — and classifies risk by pattern count over the patch, so the orchestrator sees integers rather than a diff. Every reviewer is handed these exact paths.

`RISK: high` fires on any auth/payment/migration/secret path hit, any IaC file, more than three body hits, or more than 300 changed lines. It gates two things:

| | normal | high-risk |
|---|---|---|
| `/cso` scope | `--diff` | `--diff --comprehensive` (2/10 bar, more surfaced) |
| Codex (Pass C) | only when `--codex` | **required** — `CODEX_REQUESTED=1`, `CODEX_REASON=risk`, no join budget |

The packet script prints `CODEX_REQUESTED` and `CODEX_REASON` after it applies the high-risk rule; those values, not preflight's, decide Step 5. Codex *depth* is not gated on risk — it always runs its structured review — only whether it runs and whether the verdict waits for it.

State the file count and risk class out loud. If `LINES` exceeds ~2000, warn that reviewer quality degrades at that size and that a re-run scoped to a subdirectory reads more carefully — then **proceed anyway**. This skill stops for an answer in two places only: the understanding check (Step 4.8) and a `--delta` re-review whose delta needs the user's choice (Step 1.6). Every other branch point resolves to a default and says which default it took. The check never guesses: with no answer it waits, and `--understood` is the way past it.

### Step 4.4: Lattice context and added comments (every mode)

Two cheap mechanical checks over the packet. Run both in one Bash call:

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-lattice-detect.sh" "$RUN_DIR"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-comments.sh" "$RUN_DIR"
```

**Lattice context.** `LATTICE_CONTEXT: yes` means this change has a lattice design or context doc, so Pass A runs in Step 5. `LATTICE_REASON` says how it matched: `diff_touches_context` (the diff edits a doc under `.lattice/{contexts,context,requirements,designs}`), `branch_match` (a doc's `branch:` frontmatter names this branch or the PR head branch), or `names_changed_files` (a doc names at least two of the changed files). `no` → Pass A does not run, and that is not a gap: say `lattice: not run — no lattice context for this change` once in `report.md`. The script reads file names, frontmatter, and grep hits only. **Never open the doc it names** — it is intent, and this step exists only to decide whether the lattice pass applies.

**Added comments.** `fr-comments.sh` lists every comment and docstring the diff *adds* into `packet/comments.tsv` (`file`, `start`, `end`, `kind`, `text`). Tool directives (`noqa`, `type: ignore`, `eslint-disable`, shebangs, license headers) are left out: they change behavior. Read `comments.tsv` in Step 8, not now — it is small and it is the list you print. `COMMENT_BLOCKS: 0` → nothing to drop.

### Step 4.5: Resolve the domain vocabulary (every mode)

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-ddd-vocab.sh" "$RUN_DIR"
```

Decides which vocabulary Pass U speaks in and materializes it as `packet/ddd.md`. Resolution order is the ddd-refiner's output first, tactical defaults second:

| `VOCAB` | Source | What Pass U can claim |
|---|---|---|
| `ddd-principles` | `.lattice/standards/ddd-principles.md` under `SOURCE_ROOT` | the repo's real ubiquitous language |
| `atom-defaults` | no document — generic tactical terms + nouns inferred from the diff | structural terms only |

`GLOSSARY` refines the first row: `extracted` means the document has glossary, bounded-context, or invariant sections and only those were passed through; `headings_only` means it has none and its heading list was used instead, since the section names still carry the domain's nouns. `DDD_MODE` (`overlay` / `override`) tells Pass U whether generic DDD terms are still in play alongside the document's.

**State `VOCAB` in `report.md`, always.** An explanation written in the repo's own language and one written in textbook DDD terms read almost identically and are worth very different amounts — the reader has to be told which one they got, for the same reason `HAS_GSTACK: 0` is stated rather than quietly absorbed. This is also the cheapest possible nudge toward running `/lattice:ddd-refiner`: `atom-defaults` on a repo with a real domain is a gap worth naming once, in passing, without turning the report into a pitch.

Read the printed keys, not the brief. The brief exists to be handed to Pass U by path.

### Step 4.6: UI presence check (pr mode only)

Skip unless `MODE` is `pr`. This step reports whether the change touches frontend UI, so the reader gets one honest line about it. **It never launches an app:** launching a review tree runs code that may be untrusted, with your credentials, and no signal here can tell whether the tree is your own. Never add a launch path, gated on anything.

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-ui-detect.sh" "$RUN_DIR"
```

The script reads only the packet's file list (never the diff content) and prints:

- `FRONTEND_HITS` — whether the change touches UI code at all (component frameworks, stylesheets, or files under a conventional UI directory).
- `UI_ELIGIBLE` — always `no`. The script produces a reason, never a launch.
- `UI_REASON` — the one-line explanation, which becomes `UI preview — not shown: <reason>` in `report.md`. `not pr mode`, `no frontend files in the diff`, or `app launching removed — …` when the diff does touch UI.

**Act on it in one line: write `UI preview — not shown: <UI_REASON>` to `report.md` and move on.** There is nothing to launch, navigate, screenshot, or send. The line is information — it tells a reader "there is UI in this change, open the branch to see it" — not a screenshot.

### Step 4.7: Gather PR context (whenever a PR exists)

Run this whenever a PR is discoverable — in **every** mode, not only `pr` mode. This is the step that reads the PR's description, its human discussion, and any static-analysis bot findings, into `$RUN_DIR/pr-context/` **for the producer side only**. It is the one deliberate exception to the "reviewers read the packet, not git" rule, and it is safe because nothing it writes ever reaches an isolated pass (see the forbidden-reads addition in Step 5).

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-pr-context.sh" "$RUN_DIR"
```

`PR_CONTEXT` comes back as exactly one of:

- `present` → a PR was found (already resolved in pr-remote, or discovered from the current branch's open PR in the other modes). `body.md`, `discussion.md`, and `sa-findings.md` are written. For a stack unit (`STACK_PRS` holds more than one PR), each file has a section per PR, every thread in `review-comments.json` carries its `pr` number, and the counts cover all of them. Read the printed keys, not the files — the files are for Step 7 (triage) and Pass W, handed on by path.
- `none` → no PR for this branch. This is the normal default pre-commit case. PR-context triage and Pass W simply do not apply; say nothing about them and proceed.
- `unavailable` → `gh` is missing or a call failed (`REASON` says which). State it once — PR discussion and static-analysis verification are skipped this run — and proceed. It is never a blocker.

Two keys drive later steps:

- `SA_PRESENT: yes` with `SA_TOOL: <names>` → the PR carries findings from a static-analysis tool (Wiz, Snyk, SonarCloud, CodeQL, …). **Pass W runs in Step 5** to verify each was fixed, suppressed, or dismissed. `SA_SIGNAL` is the count of tool comments/threads/checks gathered.
- `SA_PRESENT: no` → no analyzer findings on the PR (or no PR). Pass W does not run; do not mention it as a gap — there was nothing to verify.

Token discipline is preserved exactly as everywhere else: the script prints only counts and the detected tool names. It never echoes a comment or a description back through stdout. `DISCUSSION_LINES` tells you how big `discussion.md` is, so Step 7 can decide whether to read it whole or skim it.

### Step 4.8: Understanding gate (every mode)

Skip when `ARCH_APPROVED: 1`. Print `Understanding check: skipped — --understood at invocation` and go to Step 5.

This step runs **before any other reviewer**. It explains the change, discusses it with the user, and checks that the user understands it. Only then does Step 5 run. See "The understanding gate" for why.

Three parts, in order: explain (Pass U), show, check.

#### 4.8a: Pass U — explain the change

**Pass U is the first reviewer of the run, and it runs alone.** Launch it with `model: $MODEL_U` (see "Subagent models" in Step 5), in its own message: one subagent, no other subagent, no Codex command, no Step 5 work. Its prompt is the Step 5 isolation contract, verbatim, followed by this task, which replaces the contract's return-format block:

> Your job is not to find defects. Your job is to explain this change at a high level, so the reader knows what it is before anyone reviews the code. Write for an engineer who is new to this project and is asked to review this change on their first day: they know how to code, but they do not know this system, its names, or its history. Give them the big picture, not the internals. Read `{{RUN_DIR}}/packet/ddd.md` first — the repo's domain vocabulary — then `diff.patch`. Open a source file from `{{SOURCE_ROOT}}` only to learn what an existing thing is, or who calls it.
>
> When `scope.txt` has `DELTA=since-last-review`, "this change" means only the diff: what changed since the last review.
>
> **High level everywhere.** Use plain domain words. No function names, variable names, file paths, flags, table names, or library internals in the text fields. No edge cases, races, error codes, or tuning values — those are the review's job. If a sentence only makes sense to someone who has read the code, cut it. No empty verbs: "refactored", "updated", "improved", "cleaned up" say nothing.
>
> Write six things:
>
> 1. **SYSTEM** — two or three sentences. What is this part of the project, what is it for, and who or what uses it? Describe the area the change lives in as it was before the change, so a newcomer has a frame for the rest.
> 2. **BEHAVIOR** — one short paragraph, at most four sentences. What does the user see, or what does the system do now, that it did not do before? Say *before* and *now*. Name the trigger (a request, a job, a command) and the outcome. If the change has no behavior change (tooling, docs, formatting, a version bump, a config value), say exactly that and set `CHANGE_KIND: trivial`.
> 3. **FITS_INTO** — at most three lines. Where the change sits in the existing system, in big blocks only (a service, a job, a page, a store): which block starts it, which blocks it talks to, and which flow it joins. Name real existing blocks you saw.
> 4. **NEW_PARTS** — each new or changed component, class, contract (API, event, schema, file format, CLI), data owner, or cross-cutting mechanism (cache, retry, concurrency, auth, config loading). Describe each in one plain sentence — its role, not how it works. Name the file that shows it in `evidence`. A new function inside an existing module that follows that module's pattern is not a new part. When `{{RUN_DIR}}/delta/prior-architecture.md` exists, read it — the only file under `{{RUN_DIR}}/delta/` you may read — and mark each part `seen: <the earlier part>` when it is the same structural choice as one there, and `new` otherwise. When unsure, `new`.
> 5. **Three diagrams**, all Mermaid, all high level. Keep each valid Mermaid — it will be rendered. Quote any label with punctuation. No HTML.
>    - **CLASS_DIAGRAM** — a `classDiagram` of the main parts and how they connect: the new and changed components or classes, and the existing ones they connect to, with their relations (`<|--` inherits, `*--` owns, `-->` uses, `..>` depends). Show at most three key members each, only the ones that explain the role. Mark new parts with `<<new>>` and changed ones with `<<changed>>`. At most ~8 boxes. `none` only when the change adds or changes no component or class.
>    - **SEQUENCE_DIAGRAM** — a `sequenceDiagram` of the main flow, from the trigger to the outcome. The participants are big blocks (the user, a service, a job, a database, an outside system), not functions. At most ~6 participants and ~10 messages; show the happy path only. Mark the new or changed steps with a `Note over`. `none` only when the change has no flow to show.
>    - **FLOW_DIAGRAM** — a `flowchart TD` of the general flow, with the decisions the system makes on the way. Start at the trigger (a stadium node, `([...])`) and end at each outcome (stadium nodes too). Steps are boxes (`[...]`); each decision is a diamond (`{...}`) phrased as a short question, with every exit labeled (`-->|yes|`, `-->|no|`, or the value). Unlike the sequence diagram, show the main branches, not only the happy path — but only the branches that change what the user or the system gets, not error handling or retries inside one step. Mark the new or changed nodes with `:::new`, and add `classDef new stroke-width:3px` once. At most ~12 nodes and ~4 decisions. `none` only when the flow has no decision worth showing.
>    - All three are `none` for a trivial change. Do not invent a diagram.
> 6. **ALTERNATIVES** — at most three other ways to build this change, each with what it would trade (simpler, faster, safer, more coupling, more code), in one line each. Only real options for this code, judged from the code alone. `none` when there is no real choice. Do not state what the author intended — you have not been shown it.
>
> Then write **CHECK** — questions that show whether the reader knows *what* this change is. One question for a small change, two for a change with new parts. A reader who read your explanation once, with care, must be able to answer each one from it alone. Ask about:
> - what the change does, in their own words, and what is different for the user or the system after it ships;
> - what starts it and what comes out of it;
> - the role of the main new part, and where it sits in the system;
> - why the change is needed — the problem it solves.
>
> Never ask about edge cases, races, failure modes, error handling, performance, or why one implementation detail was picked over another. Those questions test whether the reader can find bugs, and finding bugs is the review's job, not the reader's. Never ask for a name, a file, or a line number. After each question, list the two or three key points a right answer must hold — each one stated in your SYSTEM, BEHAVIOR, FITS_INTO, or NEW_PARTS text. The reader will not see the key points.
>
> Good: *In your own words, what can an operator do after this change that they could not do before, and which part of the system now handles it?* Bad: *What happens when two runs start the same window at the same moment?*
>
> Write your full report to `{{RUN_DIR}}/raw/understanding.md`. Return *only* this block:
>
> ```
> PASS: understanding
> STATUS: ok | partial | failed
> CHANGE_KIND: behavior | structure | trivial
> ---
> SYSTEM: <two or three sentences — this part of the project, for a newcomer>
> ---
> BEHAVIOR: <one short paragraph — before and now>
> ---
> FITS_INTO
> - <one line>
> ---
> NEW_PARTS
> - P1: <the part in one sentence> | evidence: <file>[, <file>] | new | seen: <earlier part>
> (or "none")
> ---
> CLASS_DIAGRAM: <one fenced mermaid classDiagram block, fence and all — or "none">
> ---
> SEQUENCE_DIAGRAM: <one fenced mermaid sequenceDiagram block, fence and all — or "none">
> ---
> FLOW_DIAGRAM: <one fenced mermaid flowchart block, fence and all — or "none">
> ---
> ALTERNATIVES
> - <another way> — <what it would trade>
> (or "none")
> ---
> CHECK
> - Q1: <open question> | key: <point>; <point>[; <point>]
> ---
> NOTES: <at most two lines, only if something anomalous happened>
> FILES_READ: <comma-separated paths you opened>
> ```

`CHANGE_KIND` is `structure` when NEW_PARTS is not `none`, `behavior` when the change alters what the system does without new parts, and `trivial` otherwise.

Audit Pass U's `FILES_READ` against the forbidden list now, by the Step 6 rules. Pass U may read `delta/prior-architecture.md`; any other `delta/` path is a leak. **A Pass U leak is the worst leak there is**: an explanation built from a plan, a PR title, or `pr-context/` restates the author's claim, and the check would then test the user against the claim, not the code. On a leak, re-spawn it once; on a second leak, prefix the block `[intent-contaminated]` and say so.

Then branch:

- `STATUS: failed`, or no block → record `ARCH_GATE='failed'`, print `⚠ understanding check did not run — Pass U failed` and go to Step 5. Name it in the Step 8 reduced-coverage line. The gate never blocks the review of a change it could not read.
- `CHANGE_KIND: trivial` → show the block (4.8b) without questions, record `ARCH_GATE='trivial'`, print `No behavior change — reviewing the implementation.` and go to Step 5.
- `DELTA_PRIOR_ARCH_GATE: approved` (the user understood the last review) and no part is marked `new` → show the block (4.8b) without questions, record `ARCH_GATE='carried'`, print `You understood the last review of this PR, and this delta adds no new parts — reviewing the implementation.`, and go to Step 5.
- Otherwise → show (4.8b), then check (4.8c). After an understood last review, ask only about the `new` parts, and say `Seen at the last review: P<k>, …` for the rest.

#### 4.8b: Show the change

Write it as a normal chat reply in this shape. The fence only shows the shape — do not print it:

````text
**The system in brief**

<SYSTEM, verbatim>

**What this change does** (<branch, or PR #<n>: <title>>)

<BEHAVIOR, verbatim>

**How it fits**
- <FITS_INTO lines>

**New parts**   (only when NEW_PARTS is not none)
- **P1. <part>** (<evidence file links>)

**Main parts** (class diagram)   (only when CLASS_DIAGRAM is not none)
<the rendered class diagram — see below>

**Main flow** (sequence diagram)   (only when SEQUENCE_DIAGRAM is not none)
<the rendered sequence diagram — see below>

**Decisions** (flow diagram)   (only when FLOW_DIAGRAM is not none)
<the rendered flow diagram — see below>

**Alternatives**   (only when ALTERNATIVES is not none)
- **<alternative>:** <trade-off>

⚠ The PR title says <x>; the code says <y>.   (only when they disagree)
````

Rules:

- **No code block around the explanation.** It is normal chat text. The only code blocks it may hold are the ` ```mermaid ` fallbacks below. File paths are links, as in Step 8.
- **Print Pass U's text verbatim.** Do not rewrite, "improve", or merge it with what you know. You hold the producer context; Pass U does not, and that is the point.
- **Render each diagram in Excalidraw, do not print its source.** Write the CLASS_DIAGRAM source (without the fence) to `$RUN_DIR/ui/class.mmd`, the SEQUENCE_DIAGRAM source to `$RUN_DIR/ui/sequence.mmd`, and the FLOW_DIAGRAM source to `$RUN_DIR/ui/flow.mmd` — skip a field that is `none` — and render them:

  ```bash
  mkdir -p "$RUN_DIR/ui"
  . "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-diagrams.sh" "$RUN_DIR"
  ```

  The script uses the same offline pipeline as gstack's `/diagram` skill: each diagram becomes an editable `.excalidraw` file plus an SVG and a PNG. When gstack's render bundle or `bun` is missing, or the Excalidraw render errors, it falls back to `mmdc`, the Mermaid CLI. It prints one `DIAGRAM_<class|sequence|flow>` line per diagram: `excalidraw`, `mermaid` (the fallback rendered), `failed`, or `none` (no source).

  - **Show each PNG.** Send it with `SendUserFile` and `display: "render"`: the class PNG first, then the sequence PNG, then the flow PNG, each one named under its heading. Never open a PNG in Preview or with `open`. When the user asked to see the diagrams in the terminal, run `imgcat "<PNG_x path>"` instead. Where `SendUserFile` does not exist (a plain CLI session), print the PNG paths and say once that the user can view them with `imgcat`.
  - **Link the Excalidraw file** (`EXCALIDRAW_<x>`) under the heading, so the user can open it at excalidraw.com and edit it. When `EDITABLE_<x>: no` — Excalidraw imports a class diagram as one image — say so in a few words: the user can move and mark it up, not edit box by box.
  - **`failed`** → print that diagram's ` ```mermaid ` fence instead — one or the other per diagram, never both.
  - **Never open a PNG with Read** — an image costs ~40k tokens in your context, and you do not need to see it. Do not hand-fix invalid Mermaid; a diagram you drew carries your knowledge of the intent.
- **Alternatives the author named.** When `PR_CONTEXT: present` and `pr-context/body.md` names alternatives the author considered, or (on your own branch) this session discussed alternatives, add them under `Alternatives the author named`, labeled as such. This is for the human only — it never reaches a pass.
- **The PR title line** is the highest-value line of an explanation. When BEHAVIOR and the PR title disagree, print `⚠ The PR title says <x>; the code says <y>.` State both; do not editorialize. On a re-review, never print it: the title describes the whole PR and the explanation only the delta.
- **On a re-review** the label is `**What changed since the last review** (PR #<n>: <title>)`.

#### 4.8c: Check that the user understands

> **HARD STOP.** The run stops here until the user shows they understand the change. This overrides every unattended default in this skill.
>
> - Do not launch any subagent, Codex command, or Step 5 work before the gate opens.
> - Do not treat silence, "yes", "ok", "looks good", "I understand", or your own reading as understanding. Only an answer that holds the key points opens the gate.
> - Step 5 cannot start without it: its first action is `fr-arch-gate.sh`, which stays `closed` until `state.env` records the outcome.

First record that the gate is waiting, so an interrupted run can be resumed:

```bash
echo "ARCH_GATE='pending'" >> "$RUN_DIR/state.env"
```

Then print the questions and **end your turn**. Use plain chat, not AskUserQuestion: the answer is free text, and a list of options would turn it into a yes/no choice.

```
Before I review the implementation, a quick check that the change is clear.
Ask me anything about it first if you like.

Q1. <question>
Q2. <question>

Answer in your own words — a sentence or two each is enough.
```

Never show the key points before the user answers.

When the user replies, handle it by what it is:

- **A question about the change** → answer it in a few sentences. Use Pass U's report (`raw/understanding.md`) and, when you need to, open the one source file from `SOURCE_ROOT` that settles it — never the whole patch. Then repeat the open question(s).
- **An answer** → judge each question against its key points:
  - **got it** — the answer holds every key point, in any words. Wording, order, and names do not matter.
  - **partly** — it holds some key points and misses at least one.
  - **missed** — it holds none, or it is wrong.

  All **got it** → say `That's it.` plus one sentence that confirms the key point in your words, record the outcome, and go to Step 5 **in the same turn**:

  ```bash
  echo "ARCH_GATE='approved'" >> "$RUN_DIR/state.env"
  ```

  Any **partly** or **missed** → for each one, say what was right, then explain the missing point in two or three sentences, pointing at the new part or a diagram. Then ask **one** follow-up question on that point — not the same question again, and still about what the change is, never an edge case — and end your turn. Judge the reply the same way.
- **After two follow-up rounds** still missing a point → explain the whole change in a short paragraph, then ask the user to sum up the change in one or two sentences. A summary that holds the missing key points opens the gate. Keep going this way; do not open the gate on a guess.
- **"yes", "ok", "got it", "I understand"** with no content → `Tell me in your own words: <the question again>.`
- **An explicit waiver** ("skip the check", "just review it", "I don't need the check") → record `ARCH_GATE='waived'`, say `Check skipped at your request.`, and go to Step 5. This is the user's call; never suggest it yourself.
- **Stop words** ("stop", "cancel", "never mind") → run Step 9 to restore the tree, write no log entry, and say how to continue: re-run the review, or `--understood` to skip the check.

On your own branch the checkpoint commit stays in place while the gate waits. There, say once, with the questions: `Don't edit files until the review is done.` If the session ends while the gate waits, restore first on the next turn (`fr-restore.sh "$RUN_DIR"`), then offer to re-run.

### Step 5: Fan out all reviewers (one parallel batch)

Runs only after Step 4.8 cleared: the user showed they understand, the check was waived, the change is trivial, the understanding was carried from the last review, Pass U failed, or `--understood`. **Check it first, before launching anything:**

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-arch-gate.sh" "$RUN_DIR"
```

`ARCH_GATE: open` → launch the fan-out below. `ARCH_GATE: closed` → **launch nothing.** `REASON` is `pending` (the check is not done — go back to 4.8c) or `not_decided` (Step 4.8 did not finish). There is no override: the only ways to open the gate are the user's answer, an explicit waiver, a Pass U result, or `--understood`.

**Subagent models.** Every subagent runs on a model chosen by pass, not on the session's model. `fr-preflight.sh` printed them as `SUBAGENT_MODELS` and wrote them to `state.env` as `MODEL_<pass>`. Set `model` on each Agent call to the pass's value — `MODEL_U` (explain), `MODEL_I` (implementation), `MODEL_B` (cso), `MODEL_A` (lattice), `MODEL_K` (risk), `MODEL_W` (static-analysis), `MODEL_F` (fix check), `MODEL_R` (review army), `MODEL_X` (Codex compactor). The value `inherit` means: leave `model` off. The table lives in `scripts/fr-models.sh`; one pass can be overridden for a run with `FR_MODEL_<pass>`. Pass C is a Codex process and has its own model setting. A re-spawn uses the same model as the first launch. This skill cannot change the model of the session that runs it: run the orchestrator on Sonnet, because it only builds packets, launches passes, and triages.

Launch the Claude subagents **in a single message**:

| Pass | When |
|---|---|
| I — implementation | always |
| B — cso | always (`HAS_GSTACK: 1`) |
| A — lattice | `LATTICE_CONTEXT: yes` |
| K — risk | `pr` mode |
| R — review army | pr-remote, `ARMY_REQUESTED: 1`, `HAS_GSTACK: 1` |
| W — static-analysis | `SA_PRESENT: 1` |
| F — fix check | `DELTA: applied` and `DELTA_PRIOR_BLOCKERS` above 0 |
| C — Codex (background Bash, same message) | `CODEX_REQUESTED: 1` and `HAS_CODEX: 1` |

A pass that is not in the batch is absent by choice, not by failure. Everything downstream treats it that way.

**Pass W is not isolated, and it is launched in this same batch anyway.** It is the one pass that is *supposed* to read PR context — that is its whole job — so it takes a different contract (below) and is exempt from the forbidden-reads audit in Step 6. It reads `$RUN_DIR/pr-context/` and the packet; the isolated passes never touch either half of that.

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
> **Forbidden reads** — do not open these even if they look relevant, *and do not open them because a skill you invoke tells you to*: `{{RUN_DIR}}/pr-context/**` (the PR description, discussion, and bot findings — producer-only, and reading it turns your independent judgment into a restatement of the author's claim), `{{RUN_DIR}}/delta/**` (the last review's findings — reading them anchors you to that review instead of this diff), `.lattice/requirements/**`, `.lattice/context/**`, `.lattice/contexts/**`, `.lattice/reviews/**`, `*.plan.md`, `*.design.md`, `docs/decisions/**`, `TODOS.md`, `ONBOARDING.md`, anything under `~/.gstack/projects/**`, and any file whose purpose is to record intent rather than behavior. **Forbidden commands**: `gh pr view`, `gh issue view`, `gh pr diff --body`, `git log`. Allowed: `.lattice/standards/**`, `.lattice/learnings/**`, `.lattice/config.yaml`, `AGENTS.md`/`CLAUDE.md`, and the diffed source. (Learnings are repo-wide rules, not this change's intent — read them, never write them.)
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

When a pass below says it *replaces the return-format block* (Pass U, K, F), it replaces the last three paragraphs above — from **Report only what matters** to the end.

Pass A, B, and R run nested skills whose last steps act: `/cso` offers remediation, `/lattice:review` writes learnings, `/review` applies fixes first. A general "read-only" line does not reliably beat a nested skill's own steps, so each pass below names the sub-steps to skip by their heading, and Step 6.5 checks the result. Use `SPAWNED_SESSION: true` for non-interactive runs. **Do not set `GSTACK_HEADLESS`**: it makes gstack block on its first question instead of taking the default.

Then append the pass-specific task:

**Pass I — implementation** (every mode; no nested skill, this is a direct reading task)

The main implementation reviewer. It reads the diff once and reports what would actually go wrong. It is fast because it loads no skill.

> Review the implementation of this change. The user already understands what it does; your job is whether it does that correctly and readably. Read `diff.patch`, and open a source file from `{{SOURCE_ROOT}}` when you need a caller, a callee, or a type to judge a changed line.
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
> **Stop after its "Step 4: Produce Report". Do not run "Step 5: Harvest Learnings and Log Review."** That step asks the user to confirm which learnings enter the document and then writes them to `.lattice/learnings/operational-learnings.md` — a tracked file, so it would inject a change into the very diff under review *and* block on a question no human is there to answer. Harvesting learnings from this review is the producer's job, after triage.
> Map its `critical` findings to HIGH, `warning` to MEDIUM, and `suggestion` to LOW. Drop suggestions that only restate a checklist item with no cost in this code.

**Pass B — cso** (`{{CSO_CMD}}`, plus `--comprehensive` when high-risk)
> Run `{{CSO_CMD}}`. Honor its confidence gate — do not report below it. Cover OWASP/STRIDE on the changed surface, secrets, dependency and CI/CD exposure introduced by this diff. Give each finding a concrete exploit path in the problem field. If nothing clears the gate, return `FINDINGS: 0` — do not pad.
> **Run through "Phase 12: False Positive Filtering + Active Verification", then report and stop.** From "Phase 13: Findings Report + Trend Tracking + Remediation", produce the findings report only — no remediation planning, no remediation questions, no patches. State each fix in one sentence and let the producer decide.

**Pass K, R, W, F** — when one of them is in the batch, read its contract before you launch, and launch it in the same message as the others:

- Pass K (risk, `pr` mode) → `$FR_REFS/pass-k-risk.md`
- Pass R (review army, pr-remote with `--army`) → `$FR_REFS/pass-r-army.md`. With `--army` and `HAS_GSTACK: 0` it cannot run: name it in the Step 8 reduced-coverage line (`Pass R skipped — no gstack install`).
- Pass W (static analysis, `SA_PRESENT: 1`) → `$FR_REFS/pass-w-static-analysis.md`
- Pass F (fix check, re-review) → in `$FR_REFS/delta.md`, already read at Step 1.6

**Pass C — Codex** (background Bash, launched in the same message, not a subagent) — **only when `CODEX_REQUESTED: 1` and `HAS_CODEX: 1`.** Read `$FR_REFS/codex.md` before the launch message, then launch Pass C in that same message. Otherwise skip it; there is nothing to launch and no field to fill.

### Step 6: Join and isolation audit

**If `CODEX_REQUESTED: 1`, join Codex first** by the rules in `$FR_REFS/codex.md`. Otherwise go straight to the isolation audit below.

**Pass K raised the risk** (`pr` mode, `RISK_LEVEL: high`, but `CODEX_REQUESTED: 0` because the mechanical class was `normal`) → Codex is now required. Record it, then read `$FR_REFS/codex.md`, launch Pass C, and wait for it:

```bash
printf "%s\n" "CODEX_REQUESTED='1'" "CODEX_REASON='risk-pass'" >> "$RUN_DIR/state.env"
```

Then audit isolation. Check each `FILES_READ:` line against the forbidden list — **for the isolated passes only (I, A, B, K, R, F)**. Pass F may read `delta/prior-blockers.md`; for every other pass a `delta/` path is a leak. Pass U was already audited at the gate (Step 4.8); carry that result into the report. **Pass W is exempt:** reading `pr-context/**` is its assigned job. Any *other* pass with a `pr-context/` path is a serious leak.

- Clean → proceed.
- Forbidden path present → note the leak, downgrade that pass's confidence (its *"by design"* concessions become suspect; its bug findings do not). Re-spawn only if the leak is material and the pass is cheap.
- `FILES_READ:` missing → unverified isolation. Note it, proceed. Do not re-run on this alone.

Self-reporting is the only audit available for *reads* — a parent agent cannot inspect a subagent's tool trace, and it cannot see a `gh pr view` call at all. Treat this as a smoke detector, not a guarantee. (Step 6.5 is the one part of the contract that *is* mechanically verified; reads are not.)

None of the fan-out passes natively hunts for intent, so a forbidden read from Pass I, A, B, or the compactor is anomalous and deserves more weight than a routine leak: investigate it instead of noting it and moving on.

### Step 6.5: Reviewer mutation check (read-only enforcement)

The prompt asked the reviewers not to write. This verifies it, because a subagent inherits the parent's tool access — there is no per-call tool restriction to lean on.

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-mutation-check.sh" "$RUN_DIR"
```

`LEAK: none` → proceed. `LEAK: detected` → re-run with `--revert` to quarantine and restore:

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-mutation-check.sh" "$RUN_DIR" --revert
```

The script picks its own baseline from `CHECKPOINT`, and that distinction is the whole reason it is a script and not an inline `git status`:

- `committed` and `skipped` both leave a clean tree at fan-out, so *any* dirt now came from a reviewer — the strongest form of this check. Revert is safe: tracked files go back to `HEAD`, which holds the pre-review content either way.
- `failed` has the producer's own uncommitted work interleaved with the reviewer's, and `git restore` cannot tell them apart. The script **refuses `--revert`** there and reports `REVERT: refused_checkpoint_failed`. Print the delta, name the suspect paths, hand it to the user.
- `pr_remote` is the `failed` case's shape for a different reason: nothing was ever staged, so the user's untouched work-in-progress is still sitting in the tree. A raw status here would report all of it as a reviewer leak on every single run, so the check is a baseline diff, and `--revert` is refused (`REVERT: refused_pr_remote`) for the same reason it is under `failed`.

In pr-remote mode there is a **second** tree a reviewer could have written into, and it is the one they were pointed at, so `PR_WT_LEAK` reports it separately. Dirt there counts as a leak even though it needs no revert — Step 9 deletes the worktree regardless. What matters is the inference, not the cleanup: a reviewer that ignored "do not fix" may equally have ignored the forbidden-reads list.

**Untracked files are only listed, never cleaned.** `git clean` here could delete real work — a build artifact, a watcher's output, or a file the user created a second ago. Report `UNTRACKED_REMAINING` and let them decide.

Record any violation, and treat that pass's findings as still valid but its judgment as suspect: a reviewer that ignored "do not fix" may have ignored the forbidden-reads list too.

### Step 7: Triage

You are back in the producer context with full knowledge of design intent. Work from the compact blocks. **Pass K's is not among them** — it reports a class, not defects; its `RISK_LEVEL` feeds the header only. **Pass W's is**, tagged `static-analysis`, under the static-analysis floor below. **So is Pass F's**, tagged `fix-check`, on a re-review, under the prior-blocker floor. Pass U's is not: it explains, it does not find defects. The comment list from Step 4.4 is not triaged either — it is printed as it is.

**When `PR_CONTEXT: present`, read the PR context now — this is the producer's privilege the isolated passes were denied.** Read `$RUN_DIR/pr-context/body.md` always, and `$RUN_DIR/pr-context/discussion.md` to check surviving findings against what the PR already settled (skim it rather than reading whole when `DISCUSSION_LINES` is large). Use it two ways, and only these two:

- **Do not re-raise what the thread already resolved.** A finding a maintainer explicitly dismissed in discussion, or that a later comment shows was fixed, moves to NOISE (or BY DESIGN) **with a one-line citation of the specific comment** — never dropped silently.
- **A bucket-2 "by design" may cite a decision made in the discussion**, exactly as it may cite a session decision or a standard. "The thread says the maintainer accepts X because Y" is a valid citation; "the author presumably meant to" still is not.

This does not loosen anything. The discussion justifies a *downgrade with a citation*, never an upgrade of your confidence in the code, and it never touches the security or static-analysis floors below.

Deduplicate across passes (same `file:line` + same root cause = one finding, sources merged, keep the clearest ` ```diff ` block), then assign each to exactly one bucket:

1. **BLOCKER** — a real defect with a failure you can state: *this input or state → this wrong result, crash, data loss, or exposure*. You checked that the failure holds — you read the code path, not only the reviewer's sentence. State the fix in one sentence.
5. **SHOULD FIX** — real, and worth fixing, but no failure: a readability or maintenance cost in the changed lines, a missing test, a copy of existing logic. It does not block.
2. **REAL BUT BY DESIGN** — cite the specific decision from this session, or the specific standard/doc, that makes it intentional. No citation → it goes back to bucket 1 or 5 on its merits. Non-negotiable: this is what stops the producer from rationalizing.
3. **STYLISTIC / NOISE** — one sentence on why it doesn't matter here.
4. **REVIEWER MISUNDERSTOOD** — what they got wrong. Use sparingly; bias hard against this bucket. It is the escape hatch the producer-Claude reaches for.

(The numbers are the `findings.tsv` codes. Bucket 1 must stay "blocker", because a later re-review reads its blockers from that column.)

**The blocker bar is the loop breaker.** Past runs put about seven findings per run in bucket 1, and every one of them came back as a re-review. So:

- A finding with no failure you can state is **not** a blocker, whatever its severity. Put it in bucket 5 or 3.
- Do not promote a finding to bucket 1 "to be safe". A blocker costs a full fix-and-re-review cycle.
- **On a re-review**, a new finding is a blocker only when the delta caused it. A problem in code the last review already saw goes to bucket 5 at most, with `pre-existing` in its line.

Four overrides:

- **Security floor**: a `cso` finding at HIGH or CRITICAL cannot go to bucket 3, 4, or 5 without naming the specific compensating control — the code path, config, or middleware that neutralizes it — and where it lives. Absent that, it is a BLOCKER.
- **Static-analysis floor**: a Pass W `UNADDRESSED` finding is a BLOCKER unless you can name the specific handling Pass W missed — a suppression directive it did not see, or a human dismissal reply it did not read, cited by location. It may **not** go to bucket 3, 4, or 5 on your own judgment that it "looks fine": the tool flagged it and nobody dispositioned it.
- **Prior-blocker floor** (re-review only): a Pass F OPEN line is a BLOCKER. It was already triaged as a blocker in the last review. It leaves bucket 1 in only three ways, each cited: the specific change, by `file:line` in the current code, that fixed it and Pass F missed; a maintainer's dismissal in the PR discussion (`pr-context/discussion.md`), quoted; or proof that the earlier finding was a misread, which requires that you opened the file. A blocker that leaves this way is `released` — say which of the three in `report.md` and count it in the log.
- **Convergence**: a finding raised by two or more passes cannot go to bucket 3 — but weight the convergence by how independent the sources actually are:

  | Sources agreeing | Independence | Weight |
  |---|---|---|
  | `codex` + any Claude pass | different model family, separate process, no shared context | **strongest** — treat as near-confirmed; bucket 2 needs an explicit citation |
  | `review` + any of `implementation`/`cso`/`lattice` | same model family, a separate specialist army with its own cross-model adversarial pass | moderate-to-strong |
  | `implementation` + `lattice`, or `implementation` + `cso`, or `cso` + `lattice` | same model, different checklists | moderate |

  The `codex` row exists only when Codex ran, and the `review` row only with `--army`. On a default run the only convergence available is the moderate row, and that is expected. Do not manufacture agreement that no pass produced, and do not relax the security floor to compensate for fewer lenses.

**In pr-remote mode there is no producer context, and the buckets change accordingly.** This is the one step where the mode genuinely alters your reasoning rather than your output format:

- **Bucket 2 may not cite a session decision** — there were none; the author is someone else. It admits only a standard, a config, a code path you can point at in `SOURCE_ROOT`, or a decision explicitly recorded in the PR discussion (`pr-context/discussion.md`) — the maintainer's own words in the thread, quoted. "The author presumably meant to…" is bucket 1. This is stricter than the normal rule, not looser: the usual escape hatch was legitimate only because the producer actually held the intent, and here the only intent you may cite is one someone actually wrote down on the PR.
- **Bucket 4 requires that you opened the file.** Claiming a reviewer misread code you have not read yourself, in a change you did not write, is a guess. Without the read, it stays in bucket 1.
- **The verdict vocabulary is `APPROVE` / `APPROVE-WITH-COMMENTS` / `REQUEST-CHANGES`.** Bucket 1 non-empty means `REQUEST-CHANGES`.
- Findings are **comments, not fixes.** Phrase the **Fix:** line as an **Ask:** — what you would ask for, and never edit the PR's code.

**The verdict** follows the buckets: bucket 1 non-empty → `DO-NOT-COMMIT` (pr-remote: `REQUEST-CHANGES`); otherwise bucket 5 non-empty, or comments to drop → `COMMIT-WITH-FIXES` (pr-remote: `APPROVE-WITH-COMMENTS`); otherwise `COMMIT` (pr-remote: `APPROVE`).

Write the triaged findings to `$RUN_DIR/findings.tsv` for the log: tab-separated, with the header `bucket	severity	location	sources	finding`, one row per finding. `bucket` is `1`–`5`, `location` is `<file>:<line>`, `sources` is the comma list of passes. Keep this shape: when a review is not recorded, a later re-review reads its blockers (the bucket-1 rows) from this file.

### Step 8: Report to chat

**This is the primary output.** The explanation of the change was already shown at the gate (Step 4.8b); do not print it again. Write the review as a normal chat reply, the way you would answer a person: a short verdict sentence, then bullets with a bold label, in full short sentences. It is not a report form, a log dump, or a table. The fence below only shows the shape — do not print it:

````text
**<COMMIT | COMMIT-WITH-FIXES | DO-NOT-COMMIT; pr-remote: APPROVE | APPROVE-WITH-COMMENTS | REQUEST-CHANGES>.** <one sentence: how many blockers and should-fix findings>

- **Scope:** <branch, or PR #<n> at <short sha>>, <N> files, +<a>/−<b>. Risk: <low|med|high>. Took <elapsed>.
- **Understanding:** <checked with <n> questions | waived | trivial change | carried from the last review | skipped (--understood) | did not run>.
- **Passes:** <implementation, cso[, lattice][, codex][, review][, static-analysis][, fix-check]>.
- **Re-review:** only the changes since <short PRIOR_HEAD> (last verdict <PRIOR_VERDICT>). Earlier blockers: <total> — <fixed> fixed, <open> still open.   (only when DELTA: applied)
- **Static analysis (<tool>):** <total> raised — <fixed> fixed, <suppressed> suppressed, <dismissed> dismissed, <unaddressed> unaddressed.   (only when Pass W ran)
- **⚠ Reduced coverage:** <what was missing>.   (only when a pass failed / was unavailable)

**Blockers — fix before commit (<n>)**

1. [<file>:<line>](<link>) (<sources>). <The problem and its failure, in short sentences.>
   **Fix:** <one sentence>

   ```diff
   - <current>
   + <proposed>
   ```

**Should fix — does not block (<n>)**

1. [<file>:<line>](<link>) (<sources>). <The problem, in short sentences.>

   ```diff
   ...
   ```

**Comments to drop (<n> blocks, <m> lines)**

- [<file>](<link>): lines <start>[-<end>] (<what>), <start>-<end> (docstring, <k> lines), …

**By design (<n>)**

- [<file>:<line>](<link>) (<sources>). <The finding.> By design because <the decision or standard that justifies it>.

Set aside <n> noise and <n> misread findings; they are in `report.md`. The run log is in `<RUN_DIR>`.
````

Rules:

- **Only code goes in a code block.** The ` ```diff ` blocks are the only code blocks in the review. The verdict, the scope bullets, the section labels, the findings, the comment list, and the by-design lines are normal chat text. Never wrap them, or the whole review, in a code block, and never lay them out as fixed-width columns. Names from the code (`concat_ws`, `kind = DATA_CHECK`) go in inline backticks.
- **Every `<file>:<line>` is a link.** Link to the file relative to the working directory, with `:<line>` in the target (`[pipeline.py:304](src/pipeline.py:304)`). In pr-remote the file lives under `SOURCE_ROOT`: link to its absolute path there.
- The verdict is the first line. Never bury it under a preamble.
- **Every blocker and should-fix finding shows its ` ```diff ` block** from the pass that raised it, when it has one. Copy it as the pass wrote it — do not rewrite it. When a pass gave no block and the fix is code, open the file from `SOURCE_ROOT` at that line (`sed -n '<l-2>,<l+2>p'`), and print the current lines as `-` lines in a ` ```diff ` block under the finding, so the reader at least sees the code in question.
- **Comments to drop** prints `packet/comments.tsv` as one bullet per file: the file link, then its blocks as line ranges with a few words each. A docstring prints as `docstring (<k> lines)`. More than 30 blocks → print the first 30 and `+<n> more in report.md`. In pr-remote, head it `Comments to drop — ask the author`. Omit the section when `COMMENT_BLOCKS: 0`.
- **NOISE and MISREAD are one count line in chat**, with every finding in `report.md`. BY DESIGN stays in chat, one line each: an uncited "by design" is the thing most worth seeing.
- The **Scope** bullet carries the risk — **Pass K's class** (`low`/`med`/`high`) in `pr` mode, the mechanical `RISK` (`normal`/`HIGH`) in `review` mode. If Pass K was requested but failed, fall back to the mechanical class and add ` (mechanical)`.
- For a stack unit the **Scope** bullet names every PR in it and the unit: `PRs #42–#43 at <short sha>, stack unit 1 of 3`. **The last line of the whole chat output is the stack report** from the handoff, filled in with the verdict and the blocker count: `STACK REPORT — <stack id> · unit 1/3 · PRs #42, #43 · REQUEST-CHANGES · blockers 2`. It is for the user to paste back to the orchestrator, so print it exactly in that shape. When the run stopped at the understanding check, the verdict there is `ARCH-PENDING`.
- In pr-remote mode the **Scope** bullet names the **PR and the commit reviewed**, not your branch — and it names `PR_HEAD`, which on `HEAD_DRIFT: yes` is not what `gh` reported. Add `⚠ The PR was updated during this review.` on drift, and `⚠ The PR is MERGED` (or `CLOSED`) when it is not open.
- **The Re-review bullet prints only when `DELTA: applied`.** The blocker counts come from Pass F; with no earlier blockers, print `earlier blockers: 0`. Its `<open>` count is the number of `fix-check` lines still in Blockers after triage; a released one counts as fixed.
- **The Static analysis bullet prints only when Pass W ran.** Its `<unaddressed>` count equals the number of Pass W blockers below.
- **The ⚠ Reduced coverage bullet prints only when the run actually lost a lens** — a pass that should have run failed, `HAS_GSTACK: 0` (no `/cso`), a requested or required Codex could not run, `--army` was asked for and Pass R could not run, Pass F failed (`earlier blockers not checked`), Pass U failed (`understanding check did not run`), or the user accepted a delta after a reduced or pruned last review (Step 1.6). On a high-risk run without Codex, say it plainly: `Codex is required for high-risk changes and did not run (<reason>). Run codex login, then re-run.` A pass absent by choice — lattice with no lattice context, the army without `--army`, Codex not requested — is not reduced coverage. On a clean run, omit the bullet.
- In pr-remote, blockers are phrased as **Ask:** instead of **Fix:** (comments, not fixes).
- `(<sources>)` is the merged source list (`implementation`, `lattice`, `cso`, `review`, `codex`, `static-analysis`, `fix-check`) — this is how the user sees which passes converged.
- A section with zero findings is omitted. Blockers is never omitted: with none, the verdict sentence says `No blockers.`

**When the run stopped at the understanding check** (the user stopped it, or the session ended): say: `**Understanding pending.** The implementation was not reviewed. To continue, re-run the review, or add --understood to skip the check.` No buckets — nothing was reviewed.

### Step 8.5: Codex addendum (only when Codex landed late)

Only when Codex was launched with `CODEX_REASON: asked` on a normal-risk run and finished after Step 8 printed. Follow Step 8.5 in `$FR_REFS/codex.md`.

### Step 8.6: Hand the run to `/ship`

**Skip this step when the run stopped at the understanding check** (`ARCH_GATE: pending`). No critic ran, so there is nothing to hand ship. Say `SHIP_GATE: n/a — implementation not reviewed`.

**Skip this step entirely in pr-remote mode.** The handoff arms a gate on *your* next `/ship` of *your* branch; logging someone else's PR into it would suppress findings on a branch you never reviewed. Say `SHIP_GATE: n/a — reviewed PR #<n>, not this branch` and move on.

**Run before Step 9** — it needs the checkpoint SHA, which the reset destroys.

Build the pass list from the passes that actually ran and returned `STATUS: ok`. Start from `implementation,cso`, add `lattice` only when Pass A ran (dropping any that failed), and append `,codex` **only** when Codex was requested (`CODEX_REQUESTED: 1`) *and* returned `STATUS: ok`. Then:

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-handoff.sh" \
  "$RUN_DIR" "$STATUS" "$VERDICT" "$FR_PASSES" "$RUN_DIR/findings.json"
```

- `STATUS` is `clean` only when bucket 1 is empty; otherwise `issues_found`.
- The fourth argument is the comma list of **critic** passes that returned `STATUS: ok` — drop any that failed or were unavailable, **and never include `codex` on a Codex-off run** (it never launched, so it covered nothing), and never include `understanding`, `risk`, `static-analysis`, or `fix-check`. This is load-bearing, not bookkeeping: the ship-side gate only cuts ship's `testing`/`maintainability` specialists if `lattice` is in that list, and only cuts ship's Codex passes if `codex` is. Listing `codex` when it did not run would make ship **skip** its own Codex passes on the strength of a fresh-review pass that never happened — silently removing cross-model coverage from the final gate. The default (Codex-off, no lattice context) run therefore hands ship `implementation,cso`: ship keeps its `testing`/`maintainability` specialists and its own Codex. `understanding` and `risk` report no findings, and `static-analysis` and `fix-check` map to no ship specialist — listing any of them would claim coverage that nothing produced.
- `findings.json` is a JSON array you write first. Rules for it:
  - **Only buckets 2, 3, and 4**, each as `action: "skipped"`. Those are the decisions worth carrying forward.
  - **Never log a bucket 1 (REAL BUG) finding.** Omitting it is deliberate: ship re-reviews it, which is the regression check on your fix. Logging it as `skipped` would suppress the one finding you most need re-verified.
  - `fingerprint` is exactly `path:line:category` — repo-relative path, the finding's line, the category slug lowercased. A wrong fingerprint simply fails to match and the finding resurfaces in ship. **This step fails safe in that direction**: the worst outcome is answering a review question twice, never a real bug being hidden.

**When the handoff fails** — `SHIP_GATE: will_not_fire` — say so in chat, and say what it costs: ship will re-dispatch its full Step 9 army and re-ask about findings you already triaged. This handoff has silently no-op'd in past runs (one recorded run logged `handoff_rc: -1` and nobody noticed), so the failure is announced rather than left to be discovered at ship time. It is a convenience, never a gate: continue either way.

In no-checkpoint mode, still write the entry but expect no suppression: the logged commit is the pre-existing HEAD, so every file you later commit reads as "changed since the review".

### Step 9: Restore working state

Regardless of verdict:

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-restore.sh" "$RUN_DIR"
```

Three independent undos, each separately gated, which is why this is a script:

- `RESET` drops the checkpoint commit — **only** when it actually landed. Resetting after a failed commit would throw away the user's last real commit. The script also verifies HEAD still *is* the checkpoint before resetting, so a re-run after an interrupted pass reports `skipped_already_reset` instead of eating a commit.
- `INDEX` restores the pre-review index with `git read-tree`, in exactly the two states where `git add -A` ran: `committed` and **`failed`**. `failed` is the case a "skip the restore in no-checkpoint mode" rule gets wrong — `add` had already staged everything. `read-tree` does not touch the worktree, so the staged/unstaged split comes back exactly as it was, including partially staged files that a re-`git add` by filename would have flattened.
- `WORKTREE` removes the pr-remote checkout and deletes the temporary `refs/fresh-review/pr-<n>` ref. Reported only in that mode.

Everything is skipped when `CHECKPOINT=skipped` — nothing was staged, nothing was committed, nothing to undo.

Then tell the user: "Working tree restored — staged/unstaged split is back as it was." In pr-remote mode say instead: "Your tree was never touched; the PR checkout has been removed."

This must run even on abort or error. If the user interrupts mid-review, restoring the tree is the first thing you do on the next turn — `state.env` survives, so `fr-restore.sh "$RUN_DIR"` is all it takes.

### Step 10: Persist the run log

**In pr-remote, record the review first:** follow "At Step 10: record the review" in `$FR_REFS/pr-remote.md`.

Write `$RUN_DIR/report.md` — and because chat is now lean, this file is where the **long form** goes: the Step 8 chat output, plus everything trimmed off it (the explanation from Step 4.8b, the questions, the user's answers and how each was judged, the NOISE and MISREAD findings in full, the full comment list, the Pass K risk rationale and factor line, the full pass inventory line, the UI-preview line, the structural "not covered here — /ship owns …" note, the PR-context and static-analysis summary, the scope, and the isolation-audit result). Nothing that used to be in chat is lost; it just lives here now. Then read `$FR_REFS/run-log.md`, and write `$RUN_DIR/run.json` and append it to the index as it says.

## Failure modes and recovery

- **Checkpoint commit fails** (`CHECKPOINT: failed`) → no-checkpoint mode (Step 3), document it, and **still run `fr-restore.sh`** — `git add -A` already ran, so the index needs restoring even though there is no commit to reset.
- **Unmerged index** (`STOP_REASON: unmerged_index`) → stop at preflight. Resolve the conflict, then re-run.
- **A pass returns nothing / errors** → log it as skipped, drop it from the `passes` list in Step 8.6, and continue. No single pass is blocking, but the verdict must name the absent lens.
- **A pass ignores the compact return contract** and dumps prose → do not re-read it; note it in NOTES, extract findings from its `raw/` file with a compactor subagent as in Step 6.
- **Codex times out / fails** (only possible when `--codex` was requested) → verdict ships Claude-only, `CODEX_FAILED` in the log, the `codex` pass kept with `"status":"failed"`. Never substitute a Claude pass for it. Fix is `codex login` and re-run.
- **High-risk run without Codex** (`RISK: high` or Pass K `high`, and `HAS_CODEX: 0` or Codex failed) → a named gap, not a silent one. Print the high-risk reduced-coverage line (Step 8), keep the `codex` pass with `"status":"failed"`, and never substitute a Claude pass for it.
- **Subagent tries to fix code** → Step 6.5 catches it; `--revert` undoes it unless the checkpoint failed.
- **User aborts midway** → `fr-restore.sh "$RUN_DIR"` first, then report what was collected.
- **Forbidden read detected** → Step 6 handles it: note, downgrade confidence, optionally re-spawn. A Pass U leak is the exception: re-spawn it, or label the explanation `[intent-contaminated]` (Step 4.8a).
- **`runs.jsonl` fails to validate** → the line is dropped, `$RUN_DIR/run.json` is kept, tell the user.
- **Handoff fails** (`SHIP_GATE: will_not_fire`) → continue, and tell the user ship will re-dispatch its full army and re-ask about triaged findings.
- **Pass U fails** → do not block. Print `⚠ understanding check did not run`, go to Step 5, name it in the reduced-coverage line, log `architecture.gate: failed`.
- **A diagram does not render** (`DIAGRAM_<x>: failed`, most often invalid Mermaid from Pass U) → print its fence as 4.8b says, note `understanding ✗ class diagram`, `understanding ✗ sequence diagram`, or `understanding ✗ flow diagram`, and still ask the check questions. Do not hand-fix it.
- **Excalidraw cannot render** (no gstack bundle, no `bun`, no browser) → `fr-diagrams.sh` falls back to `mmdc` on its own. Say once, in a few words, that the diagrams are Mermaid PNGs, not Excalidraw.
- **Pass U returns file paths and function names in SYSTEM or BEHAVIOR, check questions about edge cases or races, or invents a flow for a tooling change** → re-spawn it once with the rules repeated. On a second failure, show what it returned, note it, and still ask.
- **Pass U returns no CHECK questions for a non-trivial change** → ask one yourself from its BEHAVIOR or NEW_PARTS: *in your own words, what does this change do, and which part of the system handles it?* Judge the answer against Pass U's text, not your own knowledge of the intent.
- **`fr-comments.sh` lists a line that is not a comment** (a string that looks like one) → drop it from the printed list and note it in `report.md`. It is mechanical by design.

## What this skill does NOT do

- **Open a literal fresh Claude Code session.** For maximum isolation before a major release: `git worktree add ../review-wt HEAD`, start Claude Code there, run the commands manually.
- **Auto-apply fixes.** The calling session applies fixes after triage. This skill only diagnoses.
- **Replace a full security audit.** `/cso --diff` covers the changed surface only. A full `/cso` remains a periodic job.
- **Replace QA.** Nothing here proves the code runs. `/qa` still applies.
- **Run the CI gates.** Tests, coverage, and lint are `/ship`'s job. A `COMMIT` verdict says the code reads correctly, not that it passes.
- **Stop `/ship` from reviewing again.** Ship's pre-landing review is unconditional and reviews the *final* diff — post-fix, post-CHANGELOG, post-base-merge — a different artifact from what these passes saw. `references/ship-dispatch-gate.md` trims the parts that are genuinely duplicated; the rest is supposed to run.
- **Analyze runs across sessions.** The log is written to be analyzable; reading it is a separate tool's job.
- **Post anything to GitHub.** No `gh pr comment`, `gh pr review`, or `gh pr edit`, in any mode — an unattended run must not publish a review under the user's name. Reading the PR (Step 4.7) is read-only. If the user wants the review posted, that is a separate action they ask for.
- **Feed PR context to the isolated passes.** `pr-context/` reaches only triage and Pass W. Handing it to Pass U, I, A, B, K, R, or F breaks the skill's central invariant.
- **Re-review your own branch as a delta.** `--delta` works for pr-remote and stack units only. On your own branch, the checkpoint is reset after each run, and a normal review of the branch is the re-review.
- **Modify the PR under review.** pr-remote mode is read-only on someone else's branch. Findings are comments; the worktree is disposable and gets deleted.
- **Review a PR from another repo.** `foreign_repo` stops it. There is no local tree to materialize the head into, and a patch without its source tree produces reviewers reading the wrong file contents. Clone that repo and run there.
- **Run gstack's `/review` by default.** On your own branch `/ship` runs it; on someone else's PR it runs only with `--army`.
- **Run lattice on a change with no lattice context.** Pass A runs only when Step 4.4 finds a design or context doc for this change.
- **Review the implementation before the user understands the change.** The implementation passes wait for an answer that holds the key points, an explicit waiver, or `--understood`.
- **Remove comments itself.** It lists them; the calling session drops them.
- **Replace reading the diff.** The explanation tells you what changed and why it matters; it cannot tell you whether line 84 is right.

## Examples

**"fresh review my changes before I commit"** on a branch that adds a retry wrapper around the payments client → Steps 1–10. Pass U first says what the payments client is: the one place checkout talks to the payment provider. Then the change: *before, a timeout from the provider failed the checkout; now the client tries twice more, then fails.* It shows a class diagram with the new `RetryingClient <<new>>` wrapping the existing client, a sequence diagram of checkout → retrying client → provider, a flow diagram with the decision *timed out? → tries left? → try again or fail the checkout*, and one alternative (retry in the job queue instead — simpler, but slower to recover). It asks: *in your own words, what does a shopper see now when the provider is slow, and which part decides to try again?* The user answers "checkout no longer fails on the first timeout; the new wrapper around the client tries twice more before it gives up". That holds the key points; the gate opens. Pass I, `/cso`, and (high risk, payment path) Codex run. Chat gets one blocker with its diff — no idempotency key on the retried charge — two should-fix findings, and three added comments to drop. The double-charge risk is found by the review, not asked of the user.

**"fresh review"** on a one-line bug fix → Pass U: `CHANGE_KIND: behavior`, no new parts, no class diagram, a small sequence diagram of the fixed flow, a flow diagram with the fixed decision marked, one question. The user answers in a sentence; the review runs.

**"fresh review"** on a version bump and a README edit → Pass U: `CHANGE_KIND: trivial`. The explanation prints with no question, and the review runs.

**"fresh review, I know this change"** → `--understood`. Step 4.8 is skipped.

**"fresh review with codex"** → `--codex`. Same run plus Pass C in the background alongside the Claude passes; Step 8.5 posts an addendum if it lands late.

**"fresh review"** on a feature designed with lattice → `fr-lattice-detect.sh` finds `activate/.lattice/contexts/admin-page.md` with `branch:` matching this branch, so Pass A (lattice) joins the fan-out. On a branch with no context doc, it does not.

**"review PR 42"** → `--pr 42`. Step 1.5 builds a detached worktree at the PR head. Pass U explains the PR from the code alone, and prints `⚠ the PR title says "add refund support"; the code says a fee is recorded but never reversed` when they disagree. After the check, Pass I, `/cso`, and Pass K run; findings are `→ ask:` comments with diffs; nothing is posted to the PR. Pass R does not run.

**"review PR 42 with the full army"** → `--pr 42 --army`. Same run plus Pass R (gstack `/review`, report-only) — about 15 minutes more.

**"review PR 42"** where the CI gate ran Wiz and left findings → same run, plus Pass W. One unaddressed finding becomes a BLOCKER under the static-analysis floor.
