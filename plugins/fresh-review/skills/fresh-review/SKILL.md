---
name: fresh-review
description: |
  Pre-commit fresh-eyes code review. Orchestrates a context-isolated review pass that approximates what
  a new reviewer would catch — runs the lattice review and the gstack security audit against one shared
  diff packet, via subagents that cannot read design docs, intent, or prior session context. A
  cross-model Codex pass is off by default: it runs when the invocation asks for it ("with codex",
  "cross-model review", "codex pass"), and it is a must — no asking needed — when the diff is high-risk. Triages findings against the
  producer-context, prints the verdict and every finding to chat, and logs the run for later analysis.

  Does NOT run gstack's `/review` on your own branch. That skill is what `/ship` runs unconditionally
  at its own Step 9, on the final diff; running it here too pays for the same specialist army twice.
  This skill covers craft and security ground — plus cross-model ground when Codex is requested;
  `/ship` covers the structural specialists. The one exception is pr-remote (reviewing someone else's
  PR): there is no ship of yours to run those specialists, so that mode runs `/review` report-only as
  a pass.

  Every mode starts with an **architecture gate**, before any other reviewer runs. One isolated pass
  decides whether the change makes architecture design decisions (new components, changed
  dependencies, new contracts, moved ownership, new cross-cutting mechanisms). If it does, the skill
  shows the architecture change as a before/after diagram with pros and cons per decision, runs
  gstack's `/plan-eng-review` report-only in a subagent against it, and hard-stops for the user's
  approval. The implementation passes run only after approval. `--arch-approved` skips the gate.

  Use when the user asks to "fresh review", "fresh-eyes review", "review my changes", "pre-commit
  review", "review before commit", "review with no bias", "independent review", "what did I miss",
  "check my work before I commit", "context-free review", or "review with fresh eyes". Proactively
  suggest before any /ship, /land-and-deploy, or manual git commit when the diff exceeds ~50 lines or
  touches auth, payments, migrations, or security-sensitive code.

  Has a second mode — **pr review** — that adds a diagram-first account of what the change does,
  drawn as a Mermaid sequence/flow diagram in the repo's own domain vocabulary rather than a wall of
  prose, a low/med/high risk classification of the whole change, and a one-line note when the change
  touches frontend UI (it does not launch or screenshot the app). Use it when the user
  asks for a "pr review", "review this PR", "explain this PR", "what does this PR do", "what does this
  change do", "summarize this change/PR", "diagram this PR", "explain my changes in plain English",
  "describe this PR for a non-engineer", "write the PR description", or names a PR by number or URL
  ("review PR 42", "look at github.com/o/r/pull/42"). That mode reviews *and* narrates: it is the
  default run plus a narrator pass, a risk pass, and a UI-touch note, never a summary in place of a review.

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

Code review with enforced producer/reviewer context separation — pre-commit by default, or as a PR review that also explains the change in plain English.

## Why this skill exists

When you design, write, and review code in the same session, the reviewer-Claude already agrees with the design choices and knows the rationale. It rationalizes away its own decisions. Real review needs the reviewer to *lack* context the producer has. This skill enforces that separation by spawning subagents with strict context restrictions, optionally adding a genuinely out-of-process cross-model reviewer when the run asks for one, and then triaging their findings back in the producer context (where intent is known and "by design" can be properly justified).

The same separation turns out to be worth even more for *describing* a change than for finding fault in it. A summary written by someone who knows what the change was meant to do is a restatement of that intention; a summary built from the code alone is the only kind that can contradict it. That is what `pr` mode is for.

## Modes

Two output shapes, one machine. Every mode fans out the same critic passes against the same packet; a mode changes what *else* is produced and who the reader is. The critic passes are lattice and `/cso` always, plus Codex when the invocation asked for it or the diff is high-risk (see "The Codex opt-in, and the high-risk rule" below).

| The user's words | Preflight flags | Subject of the review | Chat output |
|---|---|---|---|
| "fresh review", "review before I commit", "what did I miss" | *(none)* | your branch | verdict + findings |
| "pr review", "explain this PR", "what does this change do", "write the PR description" | `--mode pr` | your branch | **the graph** + **one-paragraph summary** + verdict + findings |
| "review PR 42", a `github.com/…/pull/42` URL | `--pr 42` | PR 42's head commit | **the graph** + **one-paragraph summary** + verdict + findings |

The chat output is deliberately lean — the graph (rendered, not its source), one short paragraph, the verdict, the comments. The risk class, the risk factor breakdown, the full narrative sections, the pass inventory, and the coverage notes are written to `report.md`, not printed. Whenever the review subject has an associated PR (always in pr-remote; auto-discovered on your own branch), the run also gathers PR context (Step 4.7) and, if the PR carried static-analysis findings, adds one static-analysis summary line and verifies each finding was handled (Pass W).

Resolve the mode once, from the invocation, and pass it to `fr-preflight.sh`. Do not re-derive it later.

- A **number or pull URL** anywhere in the request means `--pr <that>` — which implies `--mode pr`.
- Any plain-English *"what does this do"* framing means `--mode pr` with no PR ref: same branch, same passes, plus the narrative.
- Everything else is the default. When in doubt, default. The narrative is additive, so guessing `review` costs the user a paragraph; guessing `pr` on a plain pre-commit check costs a subagent.

### The Codex opt-in, and the high-risk rule

**Codex (Pass C) is off by default. It runs when the invocation asks for it, and it is a must when the change is high-risk.** It is a separate `--codex` flag, orthogonal to `--mode` and `--pr` — add it to *any* of the three rows above. Resolve it once, from the invocation, alongside the mode:

- Pass `--codex` when the request names Codex or asks for cross-model coverage: "with codex", "codex pass", "cross-model review", "run codex too", "add a second model", "include the cross-model reviewer".
- Otherwise **omit it** — a plain "fresh review", "pr review", or "review PR 42" on a normal-risk diff gets the two Claude critics (lattice + `/cso`) and no Codex. Do not add `--codex` yourself: the high-risk rule below is mechanical and needs no flag.
- **High risk makes Codex a must.** When `fr-packet.sh` classifies `RISK: high` (Step 4), it sets `CODEX_REQUESTED=1` and `CODEX_REASON=risk` in `state.env` itself. In `pr` mode, a Pass K `RISK_LEVEL: high` on a mechanically normal diff does the same after the fan-out (Step 6). A required Codex has **no join budget**: the verdict waits for it. `CODEX_REASON` tells the two apart — `asked` (the user's flag), `risk` / `risk-pass` (forced), `none`.
- The flag is a request, not a guarantee: Pass C runs only when `CODEX_REQUESTED: 1` **and** `HAS_CODEX: 1`. If Codex was asked for or required but `codex` is not on PATH, say so — same as any other missing tool. On a high-risk run that is a loud gap, not a footnote (Step 8).

Everything downstream keys off `CODEX_REQUESTED` from `state.env`: Step 5 launches Pass C only when it is `1`, and the pass line, triage convergence, handoff, and log all treat an un-requested Codex as simply absent — distinct from a requested one that failed.

### The architecture gate

**Every mode reviews architecture before implementation.** Step 4.8 runs before any other reviewer. One cheap isolated pass (Pass D) decides whether the change makes architecture design decisions. When it finds none, the run goes on as before, with one extra line in chat. When it finds some, the skill:

1. shows the architecture change as a rendered before/after diagram, with pros and cons for each decision;
2. runs gstack's `/plan-eng-review` report-only in an isolated subagent (Pass E), scoped to architecture;
3. asks the user to approve — and runs the implementation passes (Step 5) **only after the user approves**.

The reason is order of cost. If the architecture is wrong, every implementation finding is about code that will be rewritten. The fan-out is the expensive part of a run, so it waits until the structure it reviews is agreed.

This is the one place the skill stops for an answer. It never assumes approval: when no one can answer (AskUserQuestion is unavailable or fails), the run stops at the gate, restores the tree, and says how to continue. Pass `--arch-approved` to skip the gate — for a re-run after approving, or when the user says the architecture is already agreed ("architecture approved", "skip the architecture gate"). Resolve it once, from the invocation, like `--codex`.

**`pr` mode adds two passes beyond the critics — N and K — plus a UI presence check.** Pass N (narrator) draws the changed flow as a Mermaid **sequence or flow diagram** in the repo's own DDD vocabulary, at the altitude of someone who owns the product and does not read code — a diagram, not a wall of summary prose. Pass K (risk) classifies the whole change `low` / `med` / `high` by blast radius and reversibility, so the reader sees the stakes next to the verdict. And Step 4.6 reports, in one line, whether the change touches frontend UI — it does **not** launch the app or take screenshots (launching a review tree is an RCE risk; see Step 4.6). Both passes run *alongside* the critics, never instead of them: a diagram or a risk label on an unreviewed change is how a change gets waved through on the strength of a good description.

### pr-local and pr-remote

`--pr <ref>` moves the subject of the review off your branch, and five things follow from no longer being the author:

| | `review` / `pr` on your branch | `pr` with a ref (**pr-remote**) |
|---|---|---|
| What is reviewed | merge-base..worktree | the PR head, fetched fresh |
| Source files opened from | your checkout | a detached worktree at the PR head (`SOURCE_ROOT`) |
| WIP checkpoint (Step 3) | runs | **skipped** — nothing of yours is being reviewed |
| Verdict vocabulary | `COMMIT` / `COMMIT-WITH-FIXES` / `DO-NOT-COMMIT` | `APPROVE` / `APPROVE-WITH-COMMENTS` / `REQUEST-CHANGES` |
| Triage bucket 2 ("by design") | may cite this session's decisions | **may not** — you have no intent knowledge |
| Handoff to `/ship` (Step 8.6) | runs | **skipped** — you are not shipping this |
| gstack `/review` army (Pass R) | not run — `/ship` Step 9 owns it | **runs report-only** — no ship of yours will |

The verdict vocabulary is not cosmetic. `COMMIT` on someone else's PR reads as an instruction to the wrong person about the wrong tree, and this skill's output is designed to be read verdict-first.

## Configuration

```
LATTICE_REVIEW_CMD="/lattice:review"     # Lattice standards conformance (plugin-namespaced)
CSO_CMD="/cso --diff"                    # gstack security audit, scoped to branch changes
CODEX_JOIN_BUDGET=240                    # seconds to wait for Codex after the Claude passes return
FR_RUN_RETENTION=20                      # run directories kept before pruning (env var, read by fr-log.sh)
DDD_DOC=".lattice/standards/ddd-principles.md"   # narrative vocabulary; resolved by fr-ddd-vocab.sh
```

- Review scope is resolved mechanically by `fr-preflight.sh`: `branch` (merge-base..worktree) whenever an `origin/<base>` exists to merge-base against, `working` otherwise — or `pr` (merge-base..PR head), set by `fr-pr-resolve.sh` when a PR ref was given. `branch` matches what a human PR reviewer sees, and a Lattice `checkpoint_mode: continuous` session already has WIP commits on the branch that `working` scope would silently skip.
- `/cso --diff` scopes the audit to changed files and keeps daily mode's 8/10 confidence gate. High-risk diffs upgrade to `--diff --comprehensive` (Step 4).
- **Codex is opt-in, except on high risk.** When requested (`--codex`) or required (`RISK: high`, see "The Codex opt-in, and the high-risk rule") it runs as a full pass, in the background, concurrent with the others. Otherwise it does not run at all, and the run has two critic passes rather than three. Rationale for the background invocation is in Pass C.
- **The diagram narrative and risk class are `pr` mode only.** Pass N draws the changed flow as a Mermaid diagram (rendered to PNG via `mmdc` when it is on `PATH`, otherwise printed as a fenced block); Pass K classifies the change `low`/`med`/`high`. Neither runs in the default pre-commit mode, which stays lean. The mechanical `RISK` (`normal`/`high`) from `fr-packet.sh` is unchanged and still gates `/cso` depth in every mode — it is a separate signal from Pass K's class.
- **UI presence check is `pr`-mode only and never launches anything.** `fr-ui-detect.sh` reports whether the diff touches frontend UI and Step 4.6 prints one `UI preview — not shown: <reason>` line. It does **not** launch an app or take screenshots: a review tree may hold untrusted code and provenance is not mechanically decidable, so auto-launching it is an RCE risk (Step 4.6, "Why UI preview does not launch"). It never blocks the verdict.
- **The architecture gate runs in every mode** (Step 4.8), before the fan-out. Pass D decides whether there are architecture design decisions; only when there are does Pass E (`/plan-eng-review`, report-only, architecture section) run and the user get asked to approve. `--arch-approved` skips it. The architecture diagram is rendered via `mmdc` like Pass N's, with the same fence fallback.
- **PR context and static-analysis verification are producer-side and run whenever a PR exists.** `fr-pr-context.sh` (Step 4.7) gathers the PR's description, human discussion, and any static-analysis bot findings (Wiz, Snyk, SonarCloud, CodeQL, …) into `$RUN_DIR/pr-context/` — for triage and Pass W only, never for the isolated passes. When the PR carried analyzer findings (`SA_PRESENT: 1`), Pass W (Step 5) verifies each was fixed, suppressed, or dismissed, and an unaddressed one becomes a blocker under the static-analysis floor (Step 7). Both need `gh`; with no PR or no `gh` they self-skip cleanly and the run is unchanged.

## Why gstack's `/review` is not a pass here

`/review` is the exact skill `/ship` runs at its own Step 9 — unconditionally, with no "already reviewed?" gate on dispatch. Its only filters are a `DIFF_LINES < 50` floor, scope detection, and an adaptive gate that needs 10+ dispatches at zero findings before it ever fires. `skip_eng_review` does not help: it flips one row on ship's readiness dashboard and ship then says outright to continue without blocking, because it runs its own review in Step 9 regardless.

So a fresh-review that ran `/review` and was then followed by `/ship` paid for the same seven specialists, Red Team, and adversarial subagent twice — and worse, ship's Step 9 stops for fixes and asks for a re-run, so the full army re-dispatches on every fix cycle.

The division of labor is therefore fixed, not configurable:

| | fresh-review (this skill) | `/ship` Step 9 / Step 11 |
|---|---|---|
| Craft and standards conformance | Pass A (lattice) | — |
| Security | Pass B (`/cso`, confidence-gated) | `security` specialist (ungated) |
| Cross-model review | Pass C (`codex review`) — **when `--codex` is requested, and always on `RISK: high`** | Codex structured + adversarial |
| performance, data-migration, api-contract, Red Team | **not covered** — *except pr-remote, where Pass R runs them* | owned here |
| Plain-English account of the change | `pr` mode, Pass N | — |
| Reviews which artifact | the pre-commit checkpoint, or a PR head | the final diff, post-fix, post-base-merge |

The four structural specialists and Red Team are genuinely absent from this skill. That is the trade: they run once, at ship time, against the diff that actually lands. If you want them *before* commit, the answer is `/review` directly, not this skill.

**The exception is pr-remote.** The whole argument above is written from the author's seat: `/review` is redundant here because *you* run `/ship` on this diff later, so running it twice double-bills the army. Reviewing someone else's PR that premise is false — you are not the author and you never ship this branch, so no later `/ship` ever runs these specialists on it (Step 8.6's handoff is skipped precisely because there is no ship of yours to arm). The double-billing that justified the exclusion cannot happen, and without Pass R the structural specialists would review this PR *never*, not twice. So pr-remote — and only pr-remote — runs `/review` as a report-only pass (Step 5, Pass R). It is gated on `HAS_GSTACK: 1`; with no gstack install the gap stays open and the verdict says so.

The reverse redundancy — ship re-running what *this* skill already did — is handled from the ship side by `references/ship-dispatch-gate.md`.

## Output contract

Two audiences, two artifacts. Do not confuse them.

- **Chat is for the human, and it is kept lean.** It gets the verdict on its own line and *every* finding from *every* pass, merged and triaged — plus, in `pr` mode and above the verdict, **the graph and one short paragraph** (the summary), and, when the PR carried static-analysis findings, a one-line static-analysis summary. That is the whole of it: the graph, the one-paragraph summary, the verdict, the comments. It is never a pointer to a file — "Full report at `<path>`" is not an acceptable substitute for the findings or the summary.
- **Disk carries the long form.** The full narrative sections, the risk rationale and factor breakdown, the detailed pass inventory, the UI-preview note, the coverage boilerplate, raw pass reports, the diff packet, and the run log all live in the run directory (`report.md` and `raw/`). Nothing there is required reading for the user — it is where the detail that used to crowd the chat now lives.
- **Nothing is for GitHub.** No mode posts, comments, or edits a PR. See "What this skill does NOT do".

## Token discipline

Four invariants. Every step below is built around them; violating one silently makes the run cost several times what it should.

1. **The orchestrator never loads the diff** — nor the DDD principles document, nor the PR's own content beyond what triage needs. `fr-packet.sh` classifies risk with `grep -c` over the patch and prints only counts; `fr-ddd-vocab.sh` extracts the vocabulary sections into a brief and prints only its line count; `fr-pr-context.sh` writes the PR description and discussion to disk and prints only counts (`DISCUSSION_LINES` among them). The one producer-side read is triage's: `body.md` always, `discussion.md` bounded by its line count (skim when large). The static-analysis material is never read by the orchestrator at all — it is handed to Pass W by path.
2. **Reviewers read the packet, not git — and never the PR context.** The diff is materialized once (Step 4) and every isolated pass is handed the same file paths. No isolated pass re-derives scope, runs `git diff`, or opens `pr-context/`. Pass W is the sole exception on both counts: it reads `pr-context/` because verifying analyzer findings is its whole job, and it is not a critic.
3. **Passes return compact findings; prose goes to disk.** This is the largest saving by far. `/cso` alone emits thirteen numbered phases of narrative; the compact block is a few hundred tokens. Each pass writes its full report to `$RUN_DIR/raw/` and returns only the fixed-format block in Step 5.
4. **Raw reports are not read back.** Triage runs on the compact blocks. Open a raw report only to disambiguate one specific finding, and read only that finding's section.

The same principle governs the shell work: every mechanical step is a script in `${CLAUDE_PLUGIN_ROOT}/scripts/` that prints a small delimited key block. Read the block, not the machinery. Do not reimplement a script's logic inline — the scripts are where the gating rules are actually enforced, and a hand-typed variant of one is how those rules get lost.

## Workflow

Steps run in order. Step 5 is one parallel fan-out; everything else is sequential. Steps are mode-conditional where their heading says so: **1.5** and **4.5** only run in the modes that need them, **4.6** (UI presence check) runs only in `pr` mode, **4.7** (PR context) runs in any mode when a PR is discoverable, **4.8** (architecture gate) runs in every mode unless `--arch-approved` and can end the run before Step 5, **3** and **8.6** are skipped in pr-remote, and Step 5's fan-out grows with the mode and the run — Pass N (narrative) and Pass K (risk) in `pr` mode, Pass R (the review army) additionally in pr-remote, and Pass W (static-analysis verification) in any mode when the PR carried analyzer findings. Nothing else branches on mode.

Every script takes `$RUN_DIR` and reads the rest of its inputs from `$RUN_DIR/state.env`, which `fr-preflight.sh` creates and later scripts append to. You never have to thread variables between Bash calls by hand — and because state lives on disk, a run interrupted mid-way can still be restored on the next turn.

<!-- FR:BOOTSTRAP:START -->
### Step 0: Resolve the plugin root (bootstrap)

Every script below is addressed as `${CLAUDE_PLUGIN_ROOT}/scripts/…`. Claude Code exports that variable into a plugin's own commands and hooks, but **not** into the ad-hoc Bash-tool shell this skill body drives once the Skill tool has loaded — and each Bash-tool call is a fresh shell that inherits nothing from the previous one. So it is routinely empty here, and an empty value collapses every call to `bash "/scripts/fr-*.sh"`, which fails. Resolve it once, now, and do not assume it survives into the next call.

Run this before Step 1. It keeps an ambient value when Claude Code did provide one, and otherwise locates the installed plugin deterministically:

```bash
CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$CLAUDE_PLUGIN_ROOT" ] || [ ! -f "$CLAUDE_PLUGIN_ROOT/scripts/fr-preflight.sh" ]; then
  for c in \
      "$(git rev-parse --show-toplevel 2>/dev/null)/plugins/fresh-review" \
      "$HOME/.claude/plugins/marketplaces/ShuratCode-skills/plugins/fresh-review" \
      $(ls -d "$HOME"/.claude/plugins/cache/ShuratCode-skills/fresh-review/*/ 2>/dev/null | sort -Vr); do
    [ -f "$c/scripts/fr-preflight.sh" ] && CLAUDE_PLUGIN_ROOT="$(cd "$c" && pwd)" && break
  done
fi
[ -f "$CLAUDE_PLUGIN_ROOT/scripts/fr-preflight.sh" ] \
  && echo "FR_PLUGIN_ROOT: $CLAUDE_PLUGIN_ROOT" \
  || echo "FR_PLUGIN_ROOT: UNRESOLVED"
```

Candidates are ordered most-authoritative first: an ambient value wins; then this repo's own checkout (the dev / worktree case, so local edits are what runs); then the marketplace clone; then the highest-versioned entry in the version-keyed cache. The first directory that actually holds `scripts/fr-preflight.sh` wins, so a stale or partial candidate is skipped rather than trusted.

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
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh" --arch-approved    # skip the architecture gate (Step 4.8)
```

<!-- FR:BOOTSTRAP:START -->
Run this with the plugin root from Step 0 set in the same shell — prefix the command with `CLAUDE_PLUGIN_ROOT="<the path Step 0 resolved>"`, since this fresh shell does not carry it.
<!-- FR:BOOTSTRAP:END -->
This probes the repo, resolves the review scope, creates the run directory, and writes `state.env` — including the plugin root itself, so no later step has to resolve it again. Export `RUN_DIR` from its output — every later script takes it as `$1`. Pass the flags from the Modes table verbatim, add `--codex` only when the invocation asked for it (see "The Codex opt-in, and the high-risk rule" — high risk turns Codex on later, in Step 4, without the flag), and add `--arch-approved` only when the user said the architecture is already approved (see "The architecture gate"); the script rejects an unknown flag or mode with a non-zero exit rather than falling back to a default, because a silently-defaulted `--pr` would review the local branch under someone else's PR number.

On `STATUS: stop`, tell the user and stop. `STOP_REASON` is one of:

- `not_a_repo` — nothing to do here.
- `nothing_to_review` — no dirt and no commits the base branch lacks.
- `unmerged_index` — a conflict is in progress. Do **not** checkpoint a conflicted tree; a half-merged tree is not a reviewable diff. Resolve it, then re-run.

**Neither of the last two can fire under `--pr`,** and that is deliberate: both describe the *local* tree, which is not the subject of a pr-remote review. A clean checkout on `main` is the normal state to review someone else's PR from, and `nothing_to_review` there would stop the run with a message that reads exactly like a correct answer. A conflicted index is likewise harmless in that mode — it is never staged, committed, or restored.

`AHEAD` counts commits **not in the base branch** (`$DIFF_BASE..HEAD`) — deliberately not `@{upstream}..HEAD`. Comparing a branch against its own upstream asks the wrong question: a fully pushed PR branch reports `AHEAD=0` even though its PR diff is a hundred commits wide, and a branch with no upstream falls back to `0`. Either would stop the skill with "nothing to review" while a complete, reviewable diff sits in front of it. The `@{upstream}` form survives only as the degraded fallback for when there is no `origin/$BASE` to merge-base against.

Tool-availability accounting — state each of these up front, never silently:

- `HAS_GSTACK: 0` → `/cso` does not exist here. **A critic pass cannot run.** Say so plainly, run Pass A (and Pass C if it was requested and available), label the verdict reduced-lens. Discovering this inside a subagent instead wastes the run and produces a report that looks complete but isn't. Note also that no gstack install means no `/ship` either, so the structural specialists this skill defers to will never run at all.
- `CODEX_REQUESTED: 0` → the run did not ask for Codex. Step 4 still turns it on when `RISK: high`; re-read `CODEX_REQUESTED` from the packet output there. If it stays `0`, Pass C does not run and is absent by choice, not by failure. This is the default. Do not mention missing cross-model coverage as a gap — it was not requested. Only note, once, that `--codex` is available if the user wants a second model.
- `CODEX_REQUESTED: 1` with `HAS_CODEX: 0` → Codex was asked for but `codex` is not on PATH, so Pass C **cannot** run. Say so plainly, run the Claude critics, label the verdict reduced-lens, and do not substitute a Claude pass for it. Fix is `codex login` (or installing the CLI) and re-run.
- `CODEX_REQUESTED: 1` with `HAS_CODEX: 1` → Pass C runs (Step 5).
- `HAS_GH: 0` → pr-remote is impossible. Only matters when a PR ref was given; Step 1.5 stops on it.
- `ARCH_APPROVED: 1` → the user already approved the architecture; Step 4.8 is skipped. `ARCH_APPROVED: 0` is the default and the gate runs. Pass E needs gstack: with `HAS_GSTACK: 0` the gate still detects and shows the architecture (Pass D) and still asks, but without the `/plan-eng-review` findings — say so at the gate.
- `CODEX_CFG: unknown` → `gstack-config` was not found, so the setting could not be read. Report unknown, never guess `enabled`. This setting gates *gstack's* internal Codex, not ours; Pass C runs on `CODEX_REQUESTED` and `HAS_CODEX`, never on this.

Two other outputs matter later:

- `DIRTY: 0` with `AHEAD > 0` → the branch carries commits the base does not, pushed or not. Review them: the checkpoint self-skips in Step 3, scope stays `branch`. This is the normal shape of an open PR whose work is fully committed and pushed.
- `INDEX_TREE` is a real tree object written from the pre-review index, so it carries the staged *content* of every path, not just its name. Step 9 restores from it **exactly**. A name list cannot do this: a partially staged file — some hunks in the index, others not — restores by re-staging the whole file, silently folding the unstaged hunks in and destroying the split the user built.

The run directory persists, unlike a `mktemp` scratch dir — it is the record that makes a run analyzable afterward. It lives under `.fresh-review/` when that path is already gitignored, and under the git dir otherwise. The script never appends to `.gitignore`: mutating a tracked file mid-review would inject a change into the diff under review.

`LOG_DIR` is deliberately the **common** git dir, not the per-worktree one. In a worktree `git rev-parse --git-dir` resolves to `.git/worktrees/<name>`, so an index written there would fragment across worktrees and be deleted with them — and cross-run analysis would silently see only a fraction of the history. Run directories stay local and disposable; the index in `LOG_DIR` is the durable record. Entries may therefore outlive the run directory they point at, which is expected.

### Step 1.5: Resolve the PR (pr-remote only)

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

Two resolved outputs to state out loud:

- `HEAD_DRIFT: yes` — the PR was pushed to between the `gh` call and the fetch. Not an error, but the report must name the commit actually reviewed, which is `PR_HEAD`, not what `gh` reported.
- `PR_STATE` — `MERGED` and `CLOSED` are reviewable (narrating a merged PR is a legitimate use). Just say which, so nobody acts on a `REQUEST-CHANGES` for a PR that landed last week.

**The PR title is fetched and deliberately withheld from every isolated pass.** It is in `$RUN_DIR/pr.json`, and it goes in the Step 8 header for the human to read — but never into the packet or an isolated subagent prompt. The title is the author's claim about the change; Pass N's entire value is deriving the change from the code independently, and a divergence between the two is a finding rather than an input. The body, the human discussion, and any static-analysis bot findings are fetched too — but by **Step 4.7** (`fr-pr-context.sh`) into `$RUN_DIR/pr-context/`, which is producer-only: it feeds triage and the static-analysis verification (Pass W), and is on every isolated pass's forbidden-reads list. The critics and the narrator never see it; that separation is what the "Keep passes blind" design turns on.

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

State the file count and risk class out loud. If `LINES` exceeds ~2000, warn that reviewer quality degrades at that size and that a re-run scoped to a subdirectory reads more carefully — then **proceed anyway**. This skill never blocks on a question — with one exception, the architecture gate (Step 4.8), which asks only when the change makes architecture decisions. It is meant to run unattended, including inside `/loop`. Every other branch point resolves to a default and says which default it took, and the gate itself never guesses: with no one to answer it stops, and `--arch-approved` is the way back in.

### Step 4.5: Resolve the domain vocabulary (pr mode only)

Skip unless `MODE` is `pr`.

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-ddd-vocab.sh" "$RUN_DIR"
```

Decides which vocabulary Pass N speaks in and materializes it as `packet/ddd.md`. Resolution order is the ddd-refiner's output first, tactical defaults second:

| `VOCAB` | Source | What Pass N can claim |
|---|---|---|
| `ddd-principles` | `.lattice/standards/ddd-principles.md` under `SOURCE_ROOT` | the repo's real ubiquitous language |
| `atom-defaults` | no document — generic tactical terms + nouns inferred from the diff | structural terms only |

`GLOSSARY` refines the first row: `extracted` means the document has glossary, bounded-context, or invariant sections and only those were passed through; `headings_only` means it has none and its heading list was used instead, since the section names still carry the domain's nouns. `DDD_MODE` (`overlay` / `override`) tells Pass N whether generic DDD terms are still in play alongside the document's.

**State `VOCAB` in the Step 8 output, always.** A narrative written in the repo's own language and one written in textbook DDD terms read almost identically and are worth very different amounts — the reader has to be told which one they got, for the same reason `HAS_GSTACK: 0` is stated rather than quietly absorbed. This is also the cheapest possible nudge toward running `/lattice:ddd-refiner`: `atom-defaults` on a repo with a real domain is a gap worth naming once, in passing, without turning the report into a pitch.

Read the printed keys, not the brief. The brief exists to be handed to Pass N by path.

### Step 4.6: UI presence check (pr mode only)

Skip unless `MODE` is `pr`. This step reports whether the change touches frontend UI, so the reader gets one honest line about it. **It never launches an app** — see "Why UI preview does not launch" below.

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-ui-detect.sh" "$RUN_DIR"
```

The script reads only the packet's file list (never the diff content) and prints:

- `FRONTEND_HITS` — whether the change touches UI code at all (component frameworks, stylesheets, or files under a conventional UI directory).
- `UI_ELIGIBLE` — always `no`. The script produces a reason, never a launch.
- `UI_REASON` — the one-line explanation, which becomes `UI preview — not shown: <reason>` in Step 8. `not pr mode`, `no frontend files in the diff`, or `app launching removed — …` when the diff does touch UI.

**Act on it in one line: print `UI preview — not shown: <UI_REASON>` in Step 8 and move on.** There is nothing to launch, navigate, screenshot, or send. The line is information — it tells a reader "there is UI in this change, open the branch to see it" — not a screenshot.

#### Why UI preview does not launch

Earlier drafts launched the app to screenshot the changed routes. That was removed in v0.9.0 because launching a review tree is an arbitrary-code-execution risk on the reviewer's host, and the risk cannot be gated away:

- A tree under review may hold untrusted code — a PR fetched with `--pr` (pr-remote), **or** a fork / dependabot branch checked out locally and reviewed with `--mode pr`.
- Launching it (`preview_start` on a committed `.claude/launch.json`, or a `dev`/`storybook` script) runs the author's code with the reviewer's live `gh` / cloud / DB credentials.
- **Provenance — "is this tree my own code?" — is not mechanically decidable.** A locally-checked-out untrusted branch is `REVIEW_SCOPE=branch` with `SOURCE_ROOT` pointing at your own checkout, indistinguishable from your own feature branch. Gating on scope or filesystem location (the earlier fix attempt) leaves the local-checkout door open, and git author metadata is spoofable. There is no signal here worth trusting with code execution.

So the skill does not launch, in any mode. To view the UI, open the branch yourself in your own environment where you have judged it safe to run. Do not reintroduce a launch path gated on scope, worktree disposability, or author metadata — none of those is a trust boundary.

### Step 4.7: Gather PR context (whenever a PR exists)

Run this whenever a PR is discoverable — in **every** mode, not only `pr` mode. This is the step that reads the PR's description, its human discussion, and any static-analysis bot findings, into `$RUN_DIR/pr-context/` **for the producer side only**. It is the one deliberate exception to the "reviewers read the packet, not git" rule, and it is safe because nothing it writes ever reaches an isolated pass (see the forbidden-reads addition in Step 5).

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-pr-context.sh" "$RUN_DIR"
```

`PR_CONTEXT` comes back as exactly one of:

- `present` → a PR was found (already resolved in pr-remote, or discovered from the current branch's open PR in the other modes). `body.md`, `discussion.md`, and `sa-findings.md` are written. Read the printed keys, not the files — the files are for Step 7 (triage) and Pass W, handed on by path.
- `none` → no PR for this branch. This is the normal default pre-commit case. Feature 1 and 2 simply do not apply; say nothing about them and proceed.
- `unavailable` → `gh` is missing or a call failed (`REASON` says which). State it once — PR discussion and static-analysis verification are skipped this run — and proceed. It is never a blocker.

Two keys drive later steps:

- `SA_PRESENT: yes` with `SA_TOOL: <names>` → the PR carries findings from a static-analysis tool (Wiz, Snyk, SonarCloud, CodeQL, …). **Pass W runs in Step 5** to verify each was fixed, suppressed, or dismissed. `SA_SIGNAL` is the count of tool comments/threads/checks gathered.
- `SA_PRESENT: no` → no analyzer findings on the PR (or no PR). Pass W does not run; do not mention it as a gap — there was nothing to verify.

Token discipline is preserved exactly as everywhere else: the script prints only counts and the detected tool names. It never echoes a comment or a description back through stdout. `DISCUSSION_LINES` tells you how big `discussion.md` is, so Step 7 can decide whether to read it whole or skim it.

### Step 4.8: Architecture gate (every mode)

Skip when `ARCH_APPROVED: 1`. Print `Architecture gate: skipped — approved at invocation (--arch-approved)` and go to Step 5.

This step runs **before any other reviewer**. It answers one question first: does this change make architecture design decisions? If it does, the user sees the architecture change and an engineering review of it, and approves it, before the implementation passes run. See "The architecture gate" for why.

Three parts, in order: detect (Pass D), review (Pass E), ask.

#### 4.8a: Pass D — detect the decisions

**Pass D is the first reviewer of the run, and it runs alone.** Launch it in its own message: one subagent, no other subagent, no Codex command, no Step 5 work. Its prompt is the Step 5 isolation contract, verbatim, followed by this task, which replaces the contract's return-format block:

> Your job is not to find defects. Decide whether this change makes **architecture design decisions**. If it does, show them.
>
> An architecture design decision is a structural choice that outlives this change — one another engineer would want to agree with before the code is written. Count it only when the diff shows one of these:
>
> - a new component, module, service, layer, or process — or one removed or merged;
> - a changed dependency between components: a new edge, a reversed direction, a cycle, a skipped layer;
> - a new external dependency that shapes the design: a framework, a datastore, a queue, a cache, a third-party service;
> - a new or changed contract between components: a public API, an event, a schema, a file format, a CLI surface other code relies on;
> - moved responsibility or data ownership: who owns a piece of state, where it is stored, who writes it;
> - a new cross-cutting mechanism: caching, retries, a concurrency model, an auth mechanism, an error-propagation strategy, config loading.
>
> These are **not** architecture decisions: a bug fix inside one component, a refactor that keeps every boundary, new tests, docs, formatting, a version bump, a changed config value, or a new function in an existing module that follows that module's pattern. **When unsure, answer `no`.** The implementation passes still check structure (Pass A loads the architecture atom), so a missed small decision is still reviewed; a false `yes` stops the user for nothing.
>
> Name every decision with the file(s) in the diff that show it. A decision you cannot point to does not count.
>
> When the answer is `yes`, **draw the architecture change as one Mermaid `flowchart`** with two subgraphs, `Before` and `After`. Each shows the components involved and their dependencies. Rules:
>
> - Draw only the components this change touches, plus their direct neighbours. At most ~15 nodes across both subgraphs.
> - Component, module, package, and service names are fine. Function names, line numbers, and code are not.
> - Mark new nodes and edges in `After` with `:::added` and removed ones in `Before` with `:::removed`. Define both: `classDef added stroke-width:3px` and `classDef removed stroke-dasharray:5 5`.
> - Keep it valid Mermaid — it will be rendered. Quote any label with punctuation. No HTML.
>
> Then give each decision its trade-offs, judged from the code alone: what the new structure makes easier, and what it costs (coupling, operational load, migration, a new failure mode, a contract others must now keep). At most three pros and three cons per decision. Do not state what the author intended — you have not been shown it.
>
> Write your full reasoning to `{{RUN_DIR}}/raw/architecture.md`. Return *only* this block:
>
> ```
> PASS: architecture
> STATUS: ok | partial | failed
> ARCH_DECISIONS: yes | no
> ---
> DECISIONS
> - D1: <the decision in one sentence> | evidence: <file>[, <file>]
> ---
> DIAGRAM: <one fenced mermaid flowchart, fence and all — or "none" when ARCH_DECISIONS is no>
> ---
> TRADEOFFS
> - D1 + <what it makes easier>
> - D1 − <what it costs>
> ---
> NOTES: <at most two lines, only if something anomalous happened>
> FILES_READ: <comma-separated paths you opened>
> ```

Audit Pass D's `FILES_READ` against the forbidden list now, by the Step 6 rules. A Pass D that read a plan or `pr-context/` describes the author's claim, not the code. On a leak, re-spawn it once; on a second leak, prefix the gate block `[intent-contaminated]`.

Then branch on its block:

- `ARCH_DECISIONS: no` → record `ARCH_GATE='not_needed'` in `state.env`, print `Architecture: no design decisions in this change — reviewing the implementation.` and go to Step 5.
- `STATUS: failed`, or no block → record `ARCH_GATE='failed'`, print `⚠ architecture gate did not run — Pass D failed` and go to Step 5. The gate is a filter in front of the review; it never blocks the review of a change it could not read. Name it in the Step 8 reduced-coverage line.
- `ARCH_DECISIONS: yes` → continue to 4.8b.

#### 4.8b: Show the architecture, then Pass E

**Show the diagram first**, so the user reads it while Pass E runs. Write the DIAGRAM field's Mermaid source (without the fence) to `$RUN_DIR/ui/arch.mmd`, then render it:

```bash
mkdir -p "$RUN_DIR/ui" && mmdc -i "$RUN_DIR/ui/arch.mmd" -o "$RUN_DIR/ui/arch.png"
```

On success, `SendUserFile` the PNG and do not print the fence. When `mmdc` is missing or errors, print the ` ```mermaid ` fence instead — one or the other, never both, the same rule as Pass N's graph. Do not hand-fix invalid Mermaid; a diagram you drew carries your knowledge of the intent.

Then print the decisions and their trade-offs:

```
ARCHITECTURE — <n> design decision(s) · <branch, or PR #<n>>

D1. <decision>   (<evidence files>)
    + <pro>
    − <con>
D2. ...

Running /plan-eng-review on this architecture…
```

**Then launch Pass E** — one subagent, only when `HAS_GSTACK: 1`. Its prompt is the Step 5 isolation contract, verbatim, then:

> Run `/plan-eng-review` as a **report-only engineering review of this change's architecture**. It is built as an interactive plan review. These rules override it wherever they conflict:
>
> - **Target:** the file `{{RUN_DIR}}/packet/diff.patch`. Name that path explicitly at its Scope gate, so it does not ask for a target. Trace surrounding code from `{{SOURCE_ROOT}}`. The decisions to focus on are in `{{RUN_DIR}}/raw/architecture.md` — written by another isolated pass from the code alone, so it is not author intent and you may read it.
> - **Non-interactive:** run the skill's preamble command with `GSTACK_SESSION_KIND=spawned` in front of the `gstack-skill-start` call, so it echoes `SESSION_KIND: spawned` and auto-chooses the recommended option at every decision point. Never call AskUserQuestion.
> - **Report file:** `{{RUN_DIR}}/raw/eng-review.md`. This is the output path you are explicitly given. Write nowhere else.
> - **Run:** "Scope Challenge" and Section "1. Architecture review", in full. **Skip** Sections 2–4 (code quality, tests, performance): the implementation passes review those after the user approves the architecture.
> - **Skip, by heading:** "Context Recovery", "Brain Context Load", "Brain Context (preflight)", "Prior Learnings", "Design Doc Check", "Prerequisite Skill Offer", the Scope Challenge's "Search check" and "TODOS cross-reference", any web research, "Outside Voice — Independent Plan Challenge", "TODOS.md updates", "Test Plan Artifact", the task JSONL artifact, steps 3–6 of "Required outputs" (Review Log, dashboard, navigation, learning hooks), the "EXIT PLAN MODE GATE", and "Telemetry". The design-doc, context, and learnings reads open the intent this pass must not see. The Review Log would mark ship's Eng Review row as done for a diff that is not the one that lands.
> - When the skill reaches "Blocked outcome" because the Review Log was skipped, that is expected. Stop there and report.
>
> Return the standard compact block with `PASS: eng-review` — one line per finding from the Scope Challenge and Section 1. Use category slugs that start with `architecture-` (e.g. `architecture-coupling`, `architecture-failure-mode`).

When Pass E returns, audit its `FILES_READ` (Step 6 rules), then run the mutation check now — Pass E drives a skill that writes files, and a write into the tree must be caught before the user approves anything:

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-mutation-check.sh" "$RUN_DIR"
```

Handle `LEAK: detected` exactly as Step 6.5 does. The check is safe to run again after the fan-out.

Print Pass E's findings under the decisions, severity-ordered and untriaged — they are triaged in Step 7 with everything else:

```
ENG REVIEW — /plan-eng-review, architecture only (<n> findings)
1. <SEVERITY>  <file>:<line>  <problem>
   → <fix>
```

With `HAS_GSTACK: 0`, print `ENG REVIEW — not run: no gstack install` instead, and ask anyway: the diagram and trade-offs are still worth a decision.

#### 4.8c: Hard stop — ask for approval

> **HARD STOP.** The run stops here until the user answers. This overrides "never blocks on a question" and every unattended default in this skill.
>
> - Do not launch any subagent, Codex command, or Step 5 work in the same message as the question, or before its answer arrives.
> - Do not treat silence, a timeout, a tool error, or your own reading of the architecture as approval. Only the user's explicit approve answer opens the gate.
> - Step 5 cannot start without it: its first action is `fr-arch-gate.sh`, which stays `closed` until `state.env` records `ARCH_GATE='approved'`.

Call **AskUserQuestion** once:

- question: `Approve this architecture and review the implementation?`
- header: `Architecture`
- options: `Approve — review implementation` (runs Step 5 onward) and `Reject — stop here` (the implementation is not reviewed).

Record the answer in state. Write `approved` **only** after the user's approve answer has arrived:

```bash
echo "ARCH_GATE='approved'" >> "$RUN_DIR/state.env"    # or rejected / pending
```

- **Approved** → go to Step 5. Pass D and Pass E are not re-run. Pass E's block joins triage in Step 7. A free-text answer that approves, with notes, counts as approved; put the notes in `report.md`.
- **Rejected** → skip Steps 5, 6, and 6.5. Go to Step 7 with Pass E's block as the only findings, then Step 8 (see its rejected-gate rules), skip Step 8.6, and run Steps 9 and 10. A free-text answer that does not approve counts as rejected; quote it in `report.md` as the reason.
- **No answer possible** — AskUserQuestion is unavailable, or the call fails → `ARCH_GATE=pending`. **Never assume approval.** Print the pending block from Step 8, skip Steps 5 through 8.6, and run Steps 9 and 10. The user continues by re-running with `--arch-approved` once they agree with the architecture.

### Step 5: Fan out all reviewers (one parallel batch)

Runs only after Step 4.8 cleared: no architecture decisions, the gate was skipped, Pass D failed, or the user approved. **Check it first, before launching anything:**

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-arch-gate.sh" "$RUN_DIR"
```

`ARCH_GATE: open` → launch the fan-out below. `ARCH_GATE: closed` → **launch nothing.** `REASON` is `rejected` or `pending` (follow Step 4.8c's branch for it) or `not_decided` (Step 4.8 did not finish — go back and finish it). There is no override: the only ways to open the gate are the user's approval, a Pass D result, or `--arch-approved`.

Launch the Claude subagents **in a single message** — two in `review` mode (Pass A, Pass B), four in `pr` mode (adds Pass N narrative and Pass K risk), and five in pr-remote when `HAS_GSTACK: 1` (adds Pass R, the review army) — **plus Pass W (static-analysis verification) in any mode when `SA_PRESENT: 1`, and, only when `CODEX_REQUESTED: 1` (asked for, or forced by `RISK: high`), the Codex background command in the same message.** When Codex was not requested there is no Pass C to launch; the fan-out is Claude-only and everything downstream treats Codex as absent. When `SA_PRESENT: 0` there is no Pass W — the PR raised no analyzer findings, or there is no PR. Codex overlapping the others is the entire reason it stopped being a latency problem, and Pass N, Pass K, and Pass W are cheap enough that adding them changes wall time by roughly nothing.

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
> **Forbidden reads** — do not open these even if they look relevant, *and do not open them because a skill you invoke tells you to*: `{{RUN_DIR}}/pr-context/**` (the PR description, discussion, and bot findings — producer-only, and reading it turns your independent judgment into a restatement of the author's claim), `.lattice/requirements/**`, `.lattice/context/**`, `.lattice/contexts/**`, `.lattice/reviews/**`, `*.plan.md`, `*.design.md`, `docs/decisions/**`, `TODOS.md`, `ONBOARDING.md`, anything under `~/.gstack/projects/**`, and any file whose purpose is to record intent rather than behavior. **Forbidden commands**: `gh pr view`, `gh issue view`, `gh pr diff --body`, `git log`. Allowed: `.lattice/standards/**`, `.lattice/learnings/**`, `.lattice/config.yaml`, `AGENTS.md`/`CLAUDE.md`, and the diffed source. (Learnings are repo-wide rules, not this change's intent — read them, never write them.)
>
> **Do not infer author intent** from commit messages, docstrings, TODOs, or comments. Judge the code on observable behavior alone. "The comment says it's fine" is not evidence.
>
> **Non-interactive**: treat your session as `SPAWNED_SESSION: true`. Any gstack skill you invoke has a spawned-session block ("Skill routing") that applies: never call AskUserQuestion, auto-choose the recommended option, report in prose. Never wait for input — take the default, state the assumption inline, continue.
>
> **Do not fix anything.** No Edit, no Write outside `{{RUN_DIR}}`, no commits, no `git add`. This overrides any fix-first, auto-fix, remediation, or learnings-harvest step in a skill you invoke: report what you *would* change and stop there. Diagnose only.
>
> **Return format — this is a hard contract.** Write your full narrative report to `{{RUN_DIR}}/raw/{{PASS}}.md`. Return to me *only* the block below, with no preamble, no summary, no restated code, and no closing commentary. Findings severity-ordered, maximum 25; if you truncate, say so in NOTES.
>
> ```
> PASS: {{PASS}}
> STATUS: ok | partial | failed
> FINDINGS: <count>
> ---
> <CRITICAL|HIGH|MEDIUM|LOW>|<file>:<line>|<category-slug>|<problem in one sentence>|<fix in one sentence>
> ---
> NOTES: <at most two lines, only if something anomalous happened>
> FILES_READ: <comma-separated paths you opened>
> ```

#### Why each pass also carries an explicit stop list

Each of these commands is a full interactive workflow that ends in *acting*, not merely reporting: `/cso` ends in a remediation conversation, `/lattice:review` ends by writing to a tracked file, and `/review` (Pass R) is fix-first — its Step 5 auto-applies mechanical fixes to the tree before it ever asks. A generic "be non-interactive and read-only" in the isolation contract does not reliably beat a nested skill's own numbered steps — the subagent is reading that skill as executable instructions, and the last instruction it reads wins. So each pass below names the specific sub-steps to skip, *by their heading*, and Step 6.5 verifies the outcome mechanically rather than trusting the prompt. Both are needed: the prompt sets intent, the check catches the miss.

Two clarifications on the non-interactive lever, since it is easy to reach for the wrong one:

- `SPAWNED_SESSION: true` is the mode we want. gstack's own spawned-session block ("Skill routing" in `~/.claude/skills/cso/SKILL.md`) tells the skill to auto-choose the recommended option instead of calling AskUserQuestion.
- **Do not set `GSTACK_HEADLESS`.** It classifies the session as `headless`, and gstack's AskUserQuestion-failure fallback maps `headless` to `BLOCKED — stop and wait` (`~/.claude/skills/gstack/bin/gstack-session-kind`). That is the opposite of unattended: it would hang the pass on the first question rather than defaulting past it.

Then append the pass-specific task:

**Pass A — lattice** (`{{LATTICE_REVIEW_CMD}}`)
> Run `{{LATTICE_REVIEW_CMD}}` against the packet. Apply atoms conditionally: clean-code always; architecture, DDD, secure-coding, test-quality only when the delta touches their domain.
> **Stop after its "Step 4: Produce Report". Do not run "Step 5: Harvest Learnings and Log Review."** That step asks the user to confirm which learnings enter the document and then writes them to `.lattice/learnings/operational-learnings.md` — a tracked file, so it would inject a change into the very diff under review *and* block on a question no human is there to answer. Harvesting learnings from this review is the producer's job, after triage.

**Pass B — cso** (`{{CSO_CMD}}`, plus `--comprehensive` when high-risk)
> Run `{{CSO_CMD}}`. Honor its confidence gate — do not report below it. Cover OWASP/STRIDE on the changed surface, secrets, dependency and CI/CD exposure introduced by this diff. Give each finding a concrete exploit path in the problem field. If nothing clears the gate, return `FINDINGS: 0` — do not pad.
> **Run through "Phase 12: False Positive Filtering + Active Verification", then report and stop.** From "Phase 13: Findings Report + Trend Tracking + Remediation", produce the findings report only — no remediation planning, no remediation questions, no patches. State each fix in one sentence and let the producer decide.

**Pass N — narrative** (pr mode only; no nested skill, this is a direct reading task)

The critics answer *is this correct*. Pass N answers *what is this*, for a reader who owns the product and does not read code. Append this to the isolation contract, replacing its return-format block:

> Your job is not to find defects — three other passes are doing that, and a defect you notice is theirs to report, not yours. Your job is to say what this change **does**, and above all to **draw the flow it changes as a diagram**, in this repo's own domain language, for a reader who owns the product and does not read code.
>
> Read `{{RUN_DIR}}/packet/ddd.md` first — it is this repo's domain vocabulary, and `VOCAB` there tells you whether it is the project's real ubiquitous language or generic tactical terms. Then read `diff.patch`. Open a source file from `{{SOURCE_ROOT}}` only to learn what a thing *is* when the diff does not make that clear.
>
> **The diagram is the primary product, not decoration.** A prose wall makes the reader reconstruct the flow in their head; a diagram shows it. So the DIAGRAM field is where the change lives, and the text sections around it stay short. Rules for it:
>
> - **Emit a single Mermaid diagram** inside one ` ```mermaid ` fence. Choose the shape that fits the change: `sequenceDiagram` when the change is about *who calls whom, in what order* (a request flow, an interaction between actors or services); `flowchart TD` when it is about *decisions and states* (a lifecycle, a branching rule, a state machine). Pick one; do not emit both.
> - **Label every node and arrow in domain vocabulary**, under the same naming rule as the text below: a node may be `Customer`, `Checkout`, `Payment gateway`; it may not be `OrderServiceImpl`, `handleSubmit`, or `src/api/orders.ts`. The diagram is for the product owner, not the author.
> - **Draw only what this change touches.** Do not diagram the whole system — show the path the diff adds, removes, or reroutes, with just enough unchanged context to make it legible. Mark what is new or changed (e.g. a `Note over` in a sequence, or a distinct branch in a flowchart). At most ~12 nodes; past that you are diagramming code, not the domain — raise the altitude.
> - **Keep it syntactically valid Mermaid** — it will be rendered. No stray backticks inside the fence, no HTML, quote any label containing punctuation.
>
> **How you must write the text sections.** These are not style preferences; a narrative that breaks them is worse than no narrative, because it reads authoritative while saying nothing:
>
> - **No code, no file paths, no line numbers, no diff excerpts, no function or variable names** — in the diagram *or* the prose. One exception: a name that is *itself* a term in the domain vocabulary. `Order` may appear. `OrderServiceImpl`, `handleSubmit`, and `src/api/orders.ts` may not.
> - **No empty verbs.** "Refactored", "updated", "improved", "enhanced", "cleaned up", "various changes", "better error handling" all say nothing. Say what is now true that was not true before.
> - Present tense, active voice, one idea per line. At most six bullets in any section — the diagram carries the detail, so the text stays terse.
> - **Never state what the author intended.** You have not been shown it and you are not permitted to look. Describe what the code now does. "This aims to…" and "the goal is…" are both out of bounds; "a customer can now…" is what you are for.
> - **If the change has no domain meaning, say exactly that.** Tooling, CI, build config, formatting, dependency bumps, and test-only changes are real work with no domain story. Set `DIAGRAM: none`, put the explanation in HEADLINE, and leave the domain sections at `none`. Inventing a flow diagram for a build change is the single worst outcome available to you — it is the failure that makes every future narrative untrustworthy. A dependency bump is not a sequence diagram.
>
> Write your full narrative (including the diagram) to `{{RUN_DIR}}/raw/narrative.md`. Return *only* this block:
>
> ```
> PASS: narrative
> STATUS: ok | partial | failed
> VOCAB_USED: <terms from the brief you actually used, comma-separated; empty if none applied>
> ---
> HEADLINE: <one or two sentences — what this change makes true or possible>
> ---
> DIAGRAM: <a single fenced mermaid block (sequenceDiagram or flowchart), fence and all — or the literal word "none" for a change with no flow>
> ---
> NEW OR CHANGED RULES
> - <a condition the system now guarantees, or has stopped guaranteeing — or "none">
> ---
> BOUNDARIES AND CONTRACTS
> - <what other parts of the system, or other teams, now see differently — or "none">
> ---
> NOT IN THIS CHANGE
> - <something a reader of your HEADLINE would reasonably assume changed, but did not>
> ---
> NOTES: <at most two lines, only if something anomalous happened>
> FILES_READ: <comma-separated paths you opened>
> ```

Three things about this pass are deliberate:

- **It is isolated exactly as hard as the critics are.** Commit messages, PR titles, plans, and design docs are all forbidden to it. That looks perverse for a summarizer — the intent is right there — until you notice that a narrative built from the author's description is a restatement of the claim, not a check on it. Built from the code alone, it is the one artifact that can *disagree* with the PR title, and that disagreement is the most valuable thing this mode produces.
- **`NOT IN THIS CHANGE` is not filler.** It is what makes the rest trustworthy: a summary that only says what happened invites the reader to assume the adjacent thing happened too. This is where a reviewer catches "wait, I thought this also covered refunds."
- **It reports no findings and gets no bucket.** Pass N never enters triage and never converges with anything. If it noticed a defect, it was told to leave it alone; if the critics missed it, the log will show it, and that is a signal about the critics rather than a reason to give the narrator a second job.

**Pass K — risk** (pr mode only; no nested skill, this is a direct assessment task)

The critics answer *is this correct* and Pass N answers *what is this*. Pass K answers *how much would it hurt if this is wrong* — a single `low` / `med` / `high` class for the change as a whole, so the human reads the verdict already knowing the stakes. gstack ships no standalone risk framework — its `/review` scores per-finding *confidence*, not change-level *blast radius* — so this pass uses the rubric below, which is fresh-review's own. It runs alongside the critics and Pass N, under the same isolation contract, and reports **exactly one** risk class plus the factors behind it. It reports no code-quality findings and never enters triage; its output is the risk header, not a bucket.

It is handed one prior: the mechanical `RISK` from `fr-packet.sh` (`normal` or `high`, from pattern counts over the patch). Treat it as a floor to argue up from, not a verdict — a `normal` mechanical class can still be `high` if the *reachability* of the change is severe, and a `high` mechanical class can settle at `med` once you read what the touched auth path actually guards. Append this to the isolation contract, replacing its return-format block:

> Your job is not to find defects and not to describe the change — other passes do those. Your job is to classify **how much damage a latent bug in this change could do**, as one of `low`, `med`, `high`, and to name the factors that set that class. Read `diff.patch`; open a source file from `{{SOURCE_ROOT}}` only to judge how far a change reaches (what calls the touched code, what it guards, whether it is behind a flag). Do not judge whether the code is *correct* — assume it might be wrong and ask *what then*.
>
> Weigh these factors. Each is `low` / `med` / `high` on its own; the overall class is driven by the **worst** that is genuinely in play, not an average — one `high` blast-radius factor makes the change at least `med` even if everything else is `low`.
>
> - **Blast radius** — how much depends on the touched code. A leaf utility used in one place is `low`; a shared library, a base class, or a hot path many callers reach is `high`.
> - **Reversibility** — how cleanly a bad outcome can be undone. A pure code change reverted by a redeploy is `low`; a database migration, a data backfill, or a destructive/irreversible operation is `high`.
> - **Security & data surface** — whether the change touches authentication, authorization, secrets, payment, PII, or a trust boundary. Any of those present is at least `med`, and `high` when the change *weakens* a check rather than merely sitting near one.
> - **Coupling & breadth** — how many distinct modules or public contracts move together. A single self-contained unit is `low`; a change that alters an API/event/schema other teams consume is `high`.
> - **Operational surface** — infra, CI/CD, deploy config, feature flags, rollout. A change that can take the pipeline or environment down is `high`; behind an off-by-default flag pulls the *effective* class down and you must say so.
> - **Test coverage of the touched paths** — whether the changed code has tests exercising it *in this diff or already present*. Well-covered lowers the class; a high-blast change with no test touching it raises it.
>
> Return *only* this block:
>
> ```
> PASS: risk
> STATUS: ok | partial | failed
> RISK_LEVEL: low | med | high
> ---
> FACTORS
> - blast-radius: <low|med|high> — <one line>
> - reversibility: <low|med|high> — <one line>
> - security-data: <low|med|high> — <one line>
> - coupling-breadth: <low|med|high> — <one line>
> - operational: <low|med|high> — <one line>
> - test-coverage: <low|med|high> — <one line>
> ---
> RATIONALE: <one or two sentences — which factor(s) set the overall class, and why it is not a step lower>
> ---
> NOTES: <at most two lines, only if something anomalous happened>
> FILES_READ: <comma-separated paths you opened>
> ```

Two things about this pass:

- **The overall class is the worst live factor, not the mean.** Averaging is how a migration behind five safe factors gets called `low`. A reader glances at one word; that word has to reflect the thing that can actually hurt them, which is the maximum, not the middle.
- **It classifies the change, not the code's quality.** A beautifully-written change to the payment path is still `high`; a sloppy change to a debug log is still `low`. Risk is about consequence-if-wrong, and it is deliberately orthogonal to whether the critics found anything — a `high`-risk change with zero findings is exactly the case worth flagging as "clean, but tread carefully."

**Pass R — review army** (pr-remote only; `CHECKPOINT: pr_remote` **and** `HAS_GSTACK: 1`)

This is the pass that exists because pr-remote is the one mode where nobody runs `/ship`. On your own branch the structural specialists — `performance`, `data-migration`, `api-contract`, and Red Team — run at ship's Step 9 against the diff you land, so this skill leaves them out on purpose (see "Why gstack's `/review` is not a pass here"). Reviewing someone else's PR you are not the author and not the shipper: ship's Step 8.6 handoff is skipped, no later ship of yours ever touches this diff, and those specialists would otherwise never see it. So pr-remote — and only pr-remote — runs gstack's `/review` as a real pass, report-only, against the PR head.

Skip it when `HAS_GSTACK: 0`: there is no army to run. Surface it as a `⚠ reduced coverage` line in chat (Step 8) — `Pass R skipped — no gstack install; performance, data-migration, api-contract, and red-team are uncovered, and no /ship of yours reviews this PR` — because in that case the gap is real and nothing in this flow will close it. The full structural-coverage note still goes to `report.md`.

This pass does **not** take the verbatim isolation contract above — `/review` is built on `git diff` and base detection, so it must be allowed the git it needs. It runs as its own subagent, launched in the same Step 5 message as the others, with this contract instead:

> Report-only pre-landing review of a pull request you did not write. You have no prior context and no author intent; that is correct for this job.
>
> **Work in `{{SOURCE_ROOT}}`** — a detached checkout of the PR head. `cd` there first. The base to review against is `{{DIFF_BASE}}` (the merge-base SHA, already resolved); the diff under review is `{{DIFF_BASE}}..HEAD` in that worktree, identical to `{{RUN_DIR}}/packet/diff.patch`. When `/review` detects a base branch, use `{{DIFF_BASE}}` instead — a branch *name* there resolves against local refs and would diff the PR head against your own default branch.
>
> **Non-interactive**: treat your session as `SPAWNED_SESSION: true`. Any gstack skill you invoke auto-chooses the recommended option and reports in prose. Never call AskUserQuestion, never wait for input.
>
> **Run `/review`, but report-only — this overrides its fix-first design.** Run its critical pass, its Review Army specialists (`sections/review-army.md`), the PR quality score, and its adversarial review (`sections/adversarial.md`, which is where Red Team and the Codex-adversarial pass live). **Skip Step 5 "Fix-First" entirely — apply no fix, auto-fix nothing, ask nothing, and take "Skip" for every finding regardless of what `/review` marks as recommended.** **Skip Step 5.8 "Persist Eng Review result"** — you are not shipping this branch, and logging an eng-review entry for it would poison a later ship's dashboard. Do not Edit, Write outside `{{RUN_DIR}}`, `git add`, or commit anything. This overrides any fix-first, auto-fix, or persist step in `/review` or a skill it invokes: report what you *would* change and stop.
>
> **Return format — hard contract.** Write your full report to `{{RUN_DIR}}/raw/review.md`. Return to me *only* the block below, no preamble, findings severity-ordered, maximum 25:
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

**Pass W — static-analysis verification** (any mode; `SA_PRESENT: 1` only)

This is the pass that answers *did the static-analysis tool's findings actually get handled* — for a repo whose PR gate posts Wiz, Snyk, SonarCloud, CodeQL, or similar findings as comments or checks. It is the one pass that **must** read PR context, so it does not take the isolation contract at all — it is handed the gathered findings and told to check each against the code. It runs whenever `SA_PRESENT: 1`, in every mode, launched in the same Step 5 message as the others.

Skip it when `SA_PRESENT: 0` — the PR raised no analyzer findings, or there is no PR, so there is nothing to verify and no field to fill.

Its contract, in place of the isolation contract:

> Static-analysis follow-through check on a pull request. Your one job: for each finding a static-analysis tool raised on this PR, decide whether it was **handled** — and report only the ones that were **not**.
>
> **Your inputs:**
> - `{{RUN_DIR}}/pr-context/sa-findings.md` — the tool findings gathered from the PR (bot comments, inline threads with any human replies, and relevant check runs), each labelled with the tool and, where known, a `path:line`.
> - `{{RUN_DIR}}/pr-context/review-comments.json` — the raw inline threads, so you can read the full reply chain under any finding.
> - `{{RUN_DIR}}/packet/diff.patch` — the change under review.
> - Source files under `{{SOURCE_ROOT}}` — open the flagged file/line to judge whether the issue still exists.
>
> **A finding counts as HANDLED — do not report it — when any of these is true:**
> - **Fixed in the diff.** The flagged code path was changed so the issue no longer applies. Verify against `diff.patch` and the current source, not against the tool's claim.
> - **Suppressed in code.** An inline ignore directive for that tool sits on or immediately above the flagged line (e.g. a `wiz-ignore` / `nosemgrep` / `# noqa` / `sonar` suppression comment, or the tool's own documented suppression syntax). A suppression with a reason is stronger than a bare one; either counts, but note a bare suppression on a HIGH/CRITICAL finding.
> - **Dismissed in the thread.** A human (not the bot) replied under the finding accepting or dismissing it, or the tool itself marked it resolved/won't-fix. Quote the dismissing reply's author and gist in NOTES.
>
> **A finding is UNADDRESSED — report it — when none of the above holds:** the issue is still present in the code, there is no suppression, and no human dismissed it. Report it at the tool's severity if stated, else your own judgment. Do not soften a still-present HIGH finding to LOW because it is "probably fine."
>
> **Do not fix anything, do not post anything, do not edit the PR.** Diagnose only. Non-interactive: `SPAWNED_SESSION: true`; never call AskUserQuestion.
>
> **Return format — hard contract.** Write your full reasoning (every finding and its disposition) to `{{RUN_DIR}}/raw/static-analysis.md`. Return to me *only* the block below, unaddressed findings severity-ordered, maximum 25:
>
> ```
> PASS: static-analysis
> STATUS: ok | partial | failed
> TOOL: <detected tool name(s), comma-separated>
> TOTAL: <n>  FIXED: <n>  SUPPRESSED: <n>  DISMISSED: <n>  UNADDRESSED: <n>
> ---
> <CRITICAL|HIGH|MEDIUM|LOW>|<file>:<line>|static-analysis-unaddressed|<the tool's finding in one sentence>|<fix it, or add an accepted suppression / dismissal>
> ---
> NOTES: <at most three lines — e.g. which findings were dismissed and by whom>
> FILES_READ: <comma-separated paths you opened>
> ```

Two things about this pass:

- **It reports only the gaps.** A tidy PR where every Wiz finding was fixed or explicitly accepted returns `UNADDRESSED: 0` and no finding lines — that is the success case, and the counts still print in Step 8 so the reader sees the tool ran clean. Padding it with handled findings would bury the ones that matter.
- **Its unaddressed findings hit the security floor in triage.** An `UNADDRESSED` line cannot be waved into NOISE or MISREAD without naming the specific handling Pass W missed (a suppression it did not see, a reply it did not read). Absent that, it is a BLOCKER — see Step 7.

**Pass C — Codex** (background Bash, launched in the same message, not a subagent) — **only when `CODEX_REQUESTED: 1` and `HAS_CODEX: 1`.** Skip this pass entirely otherwise; there is nothing to launch and no field to fill.

```bash
case "$REVIEW_SCOPE" in
  pr)      CODEX_SCOPE=(--base "$DIFF_BASE") ;;
  working) CODEX_SCOPE=(--commit "$CHECKPOINT_SHA") ;;
  *)       CODEX_SCOPE=(--base "$BASE") ;;
esac
( cd "$SOURCE_ROOT" && codex review "${CODEX_SCOPE[@]}" \
    -c sandbox_mode="read-only" -c approval_policy="never" \
    -c 'model_reasoning_effort="high"' \
    < /dev/null > "$RUN_DIR/raw/codex.md" 2> "$RUN_DIR/raw/codex.err"
  echo $? > "$RUN_DIR/raw/codex.rc" )
```

Use `run_in_background: true`. Never set a Bash `timeout` on this — a timeout is a hard kill that burns the full budget and discards the work. Backgrounding makes the budget a *join deadline* instead, and the harness re-invokes you when the command exits.

Four things about this invocation are deliberate:

- **`codex review`, not `codex exec`.** `review` scopes natively and emits structured, severity-marked findings that drop into the triage table. `exec` returns prose that would have to be parsed. gstack uses `exec` for its adversarial pass and gates `review` at 200+ lines as its own cost control; that gating does not bind us once Codex is off the critical path.
- **Scope built from `REVIEW_SCOPE`, and therefore no custom prompt.** The CLI rejects `[PROMPT]` together with `--base` (`error: the argument '[PROMPT]' cannot be used with '--base <BRANCH>'`), so the isolation contract cannot be injected. `--base` still wins: a separate process running a different model family with no conversation history is the strongest isolation of any pass here, and handing it the base avoids spending agentic turns rediscovering the diff. The `case` above picks the scope flag per mode, and getting it wrong silently reviews the wrong commit range: `branch` diffs against the base branch (`--base "$BASE"`); `working` has no branch to diff and uses `--commit "$CHECKPOINT_SHA"`; `pr` must use `--base "$DIFF_BASE"` (the merge-base SHA, not `$BASE`) because a branch *name* there resolves against local refs and would silently diff the PR head against your own `main`.
- **`cd "$SOURCE_ROOT"`.** In review mode this is the repo root and the `cd` is a no-op. In pr-remote it is the only thing pointing Codex at the PR's commit instead of your checkout.
- **`approval_policy="never"` and `sandbox_mode="read-only"`.** A non-interactive background run that stalls on an approval prompt is indistinguishable from a slow one. Read-only also enforces "do not fix anything" at the process level rather than by instruction.
- **No `--enable web_search_cached`.** gstack enables it; for a diff review it rarely pays and it adds latency.

Budget expectations: measured floor is ~30s on an *empty* diff (process start, git probe, one model round trip). Real diffs run minutes. That floor is why Codex must never gate the verdict.

### Step 6: Join and isolation audit

**If `CODEX_REQUESTED: 0`, skip the Codex join entirely** — no pass was launched, so go straight to the isolation audit below. Otherwise check Codex once:

```bash
[ -f "$RUN_DIR/raw/codex.rc" ] && echo "CODEX_DONE rc=$(cat "$RUN_DIR/raw/codex.rc")" || echo "CODEX_RUNNING"
```

- **Done, rc=0** → compact it. Codex prepends repo instruction text and template scaffolding to its output, so do not read `codex.md` into your own context. Spawn one cheap compactor subagent: *"Read `$RUN_DIR/raw/codex.md`. It contains echoed instruction text and template scaffolding before the real content — ignore all of it. Return only the Step 5 compact block with `PASS: codex`, one line per genuine finding. No preamble."*
- **Done, rc≠0** → read `codex.err`, record `CODEX_FAILED: <reason>`, continue.
- **Still running past `CODEX_JOIN_BUDGET`** → when `CODEX_REASON` is `asked`, proceed without it. The verdict ships labeled Claude-only, and when the background task exits you post the addendum (Step 8.5). Nothing is killed; the work completes and lands on disk either way.
- **Still running, and the run is high-risk** (`RISK: high`, or `CODEX_REASON` is `risk` / `risk-pass`) → **do not proceed.** Codex is required here, so the budget does not apply. Say `Codex ⧗ required for a high-risk change — waiting` and wait for the background task to exit; the harness re-invokes you when it does.

**Pass K raised the risk** (`pr` mode, `RISK_LEVEL: high`, but `CODEX_REQUESTED: 0` because the mechanical class was `normal`) → Codex is now required. Record it, then launch Pass C exactly as in Step 5 and wait for it as above:

```bash
printf "%s\n" "CODEX_REQUESTED='1'" "CODEX_REASON='risk-pass'" >> "$RUN_DIR/state.env"
```

Then audit isolation. Check each `FILES_READ:` line against the forbidden list — **for the isolated passes only (A, B, N, K, R)**. Pass D and Pass E were already audited at the gate (Step 4.8); carry those results into the report. **Pass W is exempt:** reading `pr-context/**` is its assigned job, so a `pr-context/` path in *its* `FILES_READ` is expected, not a leak. Any *other* pass with a `pr-context/` path, on the other hand, is the most serious leak there is (see below).

- Clean → proceed.
- Forbidden path present → note the leak, downgrade that pass's confidence (its *"by design"* concessions become suspect; its bug findings do not). Re-spawn only if the leak is material and the pass is cheap.
- `FILES_READ:` missing → unverified isolation. Note it, proceed. Do not re-run on this alone.

Self-reporting is the only audit available for *reads* — a parent agent cannot inspect a subagent's tool trace, and it cannot see a `gh pr view` call at all. Treat this as a smoke detector, not a guarantee. (Step 6.5 is the one part of the contract that *is* mechanically verified; reads are not.)

Among the fan-out passes, none natively hunts for intent — that was `/review`'s habit, and `/review` no longer runs here. (Pass E's `/plan-eng-review` does hunt for design docs, which is why its prompt names those steps to skip and why it is audited at the gate.) So a forbidden read from Pass A, Pass B, or the compactor is genuinely anomalous rather than expected, and deserves more weight than a routine leak: investigate it instead of noting it and moving on.

**A forbidden read by Pass N is worse than any other pass's,** and is the one leak that should make you discard output rather than downgrade it. A critic that peeked at a design doc produces findings that are still findings. A narrator that peeked at a plan, a commit message, a PR title, or anything under `pr-context/` produces a narrative that has quietly become a *restatement of the author's claim* — indistinguishable in form from an independent reading, and it destroys the only property that made the narrative worth printing. On a Pass N leak: label the narrative `[intent-contaminated]` in the Step 8 output, or re-spawn it. Never print it clean.

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

You are back in the producer context with full knowledge of design intent. Work from the compact blocks — **neither Pass N's nor Pass K's is among them**; the narrative carries no findings and the risk pass reports a class, not defects, so both stay out of triage entirely. Pass K's `RISK_LEVEL` feeds the header and the verdict framing, never a bucket. **Pass W's block *is* among them**, tagged `static-analysis` — its `UNADDRESSED` lines are findings and enter triage like any critic's, under the static-analysis floor below. **So is Pass E's**, tagged `eng-review`, whenever the architecture gate ran it. Pass D's is not: it reports decisions, not defects.

**When `PR_CONTEXT: present`, read the PR context now — this is the producer's privilege the isolated passes were denied.** Read `$RUN_DIR/pr-context/body.md` always, and `$RUN_DIR/pr-context/discussion.md` to check surviving findings against what the PR already settled (skim it rather than reading whole when `DISCUSSION_LINES` is large). Use it two ways, and only these two:

- **Do not re-raise what the thread already resolved.** A finding a maintainer explicitly dismissed in discussion, or that a later comment shows was fixed, moves to NOISE (or BY DESIGN) **with a one-line citation of the specific comment** — never dropped silently, so the reader sees it was considered.
- **A bucket-2 "by design" may cite a decision made in the discussion**, exactly as it may cite a session decision or a standard. "The thread says the maintainer accepts X because Y" is a valid citation; "the author presumably meant to" still is not.

This does not loosen anything. The discussion is the author's and reviewers' claims about the change; it justifies a *downgrade with a citation*, never an upgrade of your confidence in the code, and it never touches the security or static-analysis floors below.

Deduplicate across passes (same `file:line` + same root cause = one finding, sources merged), then assign each to exactly one bucket:

1. **REAL BUG** — must fix before commit. State the fix in one sentence.
2. **REAL BUT BY DESIGN** — cite the specific decision from this session, or the specific standard/doc, that makes it intentional. No citation → reclassify as REAL BUG. Non-negotiable: this is what stops the producer from rationalizing.
3. **STYLISTIC / NOISE** — one sentence on why it doesn't matter here.
4. **REVIEWER MISUNDERSTOOD** — what they got wrong. Use sparingly; bias hard against this bucket. It is the escape hatch the producer-Claude reaches for.

Three overrides:

- **Security floor**: a `cso` finding at HIGH or CRITICAL cannot go to bucket 3 or 4 without naming the specific compensating control — the code path, config, or middleware that neutralizes it — and where it lives. Absent that, it is a REAL BUG.
- **Static-analysis floor**: a Pass W `UNADDRESSED` finding is a REAL BUG (bucket 1) unless you can name the specific handling Pass W missed — a suppression directive it did not see, or a human dismissal reply it did not read, cited by location. It may **not** go to bucket 3 or 4 on your own judgment that it "looks fine": the entire point is that the tool flagged it and nobody dispositioned it. This holds regardless of the tool's stated severity — an unaddressed finding is a gate on the verdict, not advice.
- **Convergence**: a finding raised by two or more passes cannot go to bucket 3 — but weight the convergence by how independent the sources actually are, because not all agreement is evidence:

  | Sources agreeing | Independence | Weight |
  |---|---|---|
  | `codex` + `lattice`, or `codex` + `cso` | different model family, separate process, no shared context | **strongest** — treat as near-confirmed; bucket 2 needs an explicit citation |
  | `review` + any of `cso`/`lattice` | same model family, but a separate process running a different specialist army with its own internal cross-model adversarial pass | moderate-to-strong |
  | `cso` + `lattice` | same model, but different checklists and a confidence gate on one side | moderate |
  | `eng-review` + `lattice` or `cso` | same model, different skill and checklist, run before the other and blind to it | moderate |

  The two `codex` rows exist only when Codex ran — i.e. `--codex` was requested and it succeeded. The `review` row exists only on pr-remote runs with gstack. **On a default (Codex-off) run the only convergence available is `cso` + `lattice`, the moderate row**, and that is expected, not a defect. Do not manufacture cross-model agreement that no pass produced.

  With only two or three critic passes, convergence is *rarer* than it would be with a nested specialist army — but not *weaker*. The rows above keep exactly the weight they state, and a finding raised by one pass alone is still a finding raised by one pass alone. Do not loosen bucket 2's citation requirement, or relax the security floor, to compensate for thinner agreement: the correct response to fewer lenses — including a run that opted out of Codex — is a more conservative verdict, not a lower bar.

**In pr-remote mode there is no producer context, and the buckets change accordingly.** This is the one step where the mode genuinely alters your reasoning rather than your output format:

- **Bucket 2 may not cite a session decision** — there were none; the author is someone else. It admits only a standard, a config, a code path you can point at in `SOURCE_ROOT`, or a decision explicitly recorded in the PR discussion (`pr-context/discussion.md`) — the maintainer's own words in the thread, quoted. "The author presumably meant to…" is bucket 1. This is stricter than the normal rule, not looser: the usual escape hatch was legitimate only because the producer actually held the intent, and here the only intent you may cite is one someone actually wrote down on the PR.
- **Bucket 4 requires that you opened the file.** Claiming a reviewer misread code you have not read yourself, in a change you did not write, is a guess. Without the read, it stays in bucket 1.
- **The verdict vocabulary is `APPROVE` / `APPROVE-WITH-COMMENTS` / `REQUEST-CHANGES`.** Bucket 1 non-empty means `REQUEST-CHANGES`.
- Findings are **comments, not fixes.** Phrase the `→ fix:` line as what you would ask for, and never edit the PR's code.

**After a rejected architecture gate**, Pass E's findings are the only input. Triage them the same way. The verdict is `DO-NOT-COMMIT` (pr-remote: `REQUEST-CHANGES`) whatever the buckets hold: the user rejected the architecture, and that is the blocker.

Write the merged pre-triage findings to `$RUN_DIR/findings.tsv` for the log.

### Step 8: Report to chat

**This is the primary output.** Print it in full, in chat, in this shape. Verdict first, always.

In `pr` mode the chat output is deliberately short — the user asked for four things and only those: **the graph, a one-paragraph summary, the verdict, and the comments.** Everything Pass N and Pass K also produced (the rule/boundary/scope sections, the risk factor breakdown, the coverage and isolation notes) goes to `report.md` on disk in Step 10, not to chat. Do not print it here. The narrative block comes before the verdict, because a reader who does not yet know what the change *does* cannot evaluate a list of findings about it.

The narrative block is exactly this — a diagram, then one short paragraph:

````
WHAT THIS CHANGE DOES — <branch, or PR #<n>: <title>>

```mermaid
<the DIAGRAM field from Pass N, verbatim — ONLY when the diagram could not be rendered to an image; see below>
```

<HEADLINE from Pass N, verbatim — one short paragraph, the whole summary>
⚠ the PR title says <x>; the code says <y>.          (only when they disagree)
````

Rules for the narrative block:

- **Show the graph, not its source.** If `mmdc` is on `PATH`, render the fenced Mermaid to `$RUN_DIR/ui/flow.png`, `SendUserFile` it, and **do not also print the ` ```mermaid ` fence** — the rendered image *is* the graph, and printing the syntax underneath it is the duplication this mode fixed. Only when rendering is unavailable or fails (no `mmdc`, or an `mmdc` error) print the fence as the fallback, so the graph still reaches a client that renders Mermaid inline. One or the other, never both.
- **When `DIAGRAM: none`, print neither** — drop the fence and the image and print `(no flow diagram — this change has no domain flow)`. A tooling/config/dependency change has no sequence to draw, and inventing one is the worst outcome (Step 5, Pass N).
- **The summary is one paragraph — the `HEADLINE`, verbatim.** Do not append the `NEW OR CHANGED RULES`, `BOUNDARIES AND CONTRACTS`, or `NOT IN THIS CHANGE` sections to chat; they live in `report.md`. Print the headline as Pass N wrote it — do not rewrite it, "improve" it, or merge it with what you know about the change. You have the producer context; Pass N does not, and that is the point.
- **When the narrative and the PR title disagree, keep the one ⚠ line.** `⚠ the PR title says <x>; the code says <y>.` This is the highest-value line this mode emits and it survives the trim. State both and let the reader decide; do not editorialize.
- On a Pass N isolation leak (Step 6), prefix the block `[intent-contaminated]` or omit it entirely.

Then the review block:

```
FRESH REVIEW — <COMMIT | COMMIT-WITH-FIXES | DO-NOT-COMMIT>
                 (pr-remote: APPROVE | APPROVE-WITH-COMMENTS | REQUEST-CHANGES)
<branch, or PR #<n> @ <short sha>> · <N> files, +<a>/−<b> · risk: <low|med|high> · <elapsed>
architecture: <approved (<n> decisions) | no design decisions | skipped (--arch-approved)>   (always)
static analysis (<tool>): <total> raised — <fixed> fixed, <suppressed> suppressed, <dismissed> dismissed, <unaddressed> unaddressed   (only when Pass W ran)
⚠ reduced coverage: <what was missing>                               (only when a pass failed / was unavailable)

BLOCKERS — fix before commit (<n>)
1. <file>:<line>  [<sources>]  <problem>
   → fix: <one sentence>
2. ...

BY DESIGN (<n>)
  <file>:<line>  [<sources>]  <finding> — <the decision or standard that justifies it>

NOISE (<n>)
  <file>:<line>  [<sources>]  <finding> — <why it doesn't matter here>

MISREAD (<n>)
  <file>:<line>  [<sources>]  <finding> — <what the reviewer got wrong>

log: <RUN_DIR>
```

The chat block stays lean on purpose: **verdict, context line, static-analysis summary, findings.** The detailed pass inventory, the Pass K risk rationale and factor breakdown, the UI-preview line, and the coverage boilerplate all move to `report.md` (Step 10) — they are on disk for anyone who wants them, and out of the reader's way here.

Rules:

- The verdict is the first line of the review block, and the narrative block is the only thing permitted above it. Never bury it under a preamble.
- The context line carries `risk:` — **Pass K's class** (`low`/`med`/`high`) in `pr` mode, the mechanical `RISK` (`normal`/`HIGH`) in `review` mode. If Pass K was requested but failed, fall back to the mechanical class and add ` (mechanical)`.
- In pr-remote mode the context line names the **PR and the commit reviewed**, not your branch — and it names `PR_HEAD`, which on `HEAD_DRIFT: yes` is not what `gh` reported. Add `⚠ PR was updated during this review` on drift, and `⚠ PR state: MERGED` (or `CLOSED`) when it is not open, so nobody acts on `REQUEST-CHANGES` for something that already landed.
- **The `architecture` line always prints.** It tells the reader whether the structure was agreed before the findings below were produced. The diagram and trade-offs were already shown at the gate (Step 4.8); do not print them again here.
- **The `static analysis` line prints only when Pass W ran** (`SA_PRESENT: 1`). It gives the reader the whole feature-1 answer in one line: how many the tool raised and how they broke down. Its `<unaddressed>` count equals the number of Pass W blockers below. Omit the line entirely when no analyzer findings were on the PR.
- **The `⚠ reduced coverage` line prints only when the run actually lost a lens** — a critic pass failed, `HAS_GSTACK: 0`, a requested or required Codex could not run, or (pr-remote) Pass R could not run. On a high-risk run without Codex, say it plainly: `⚠ reduced coverage: Codex is required for high-risk changes and did not run (<reason>) — fix with codex login, then re-run`. Name what is missing in one line (e.g. `cso did not run — no gstack install`; `Pass R skipped — structural specialists and red-team not covered, and no /ship of yours reviews this PR`). On a clean full run, omit it. This is the one safety signal kept in chat; the exhaustive "what this skill structurally defers to /ship" note lives in `report.md`.
- **Every finding from every pass appears here**, in one of the four buckets. Deduplicated, with its sources tagged, but never dropped and never deferred to the report file. A bucket with zero findings collapses to a single `BY DESIGN (0)` line.
- Blockers get the full two-line treatment. The other three buckets get one line each. In pr-remote, blockers are phrased as `→ ask:` (comments, not fixes), matching the verdict vocabulary.
- `[<sources>]` is the merged source list (`lattice`, `cso`, `review`, `codex`, `static-analysis`, `eng-review`) — this is how the user sees which passes converged. `review` appears only on pr-remote runs; `static-analysis` only when Pass W ran; `eng-review` only when the architecture gate ran Pass E.
- The `log:` line is a footer, not a substitute for anything above it.

**When the architecture gate did not clear**, the review block changes:

- **Rejected** → the verdict line is `FRESH REVIEW — DO-NOT-COMMIT` (pr-remote: `REQUEST-CHANGES`), and the architecture line reads `architecture: rejected — implementation not reviewed`. Print Pass E's triaged findings in the usual buckets. Add the user's reason if they gave one.
- **Pending** → print `FRESH REVIEW — ARCHITECTURE PENDING`, then `architecture: <n> decisions awaiting approval — implementation not reviewed`, then `To continue: re-run with --arch-approved once you agree with the architecture above.` No buckets — nothing was triaged.

In both cases the narrative block (pr mode) is not printed: Pass N never ran.

If more than ~40 findings survive dedup, keep all blockers in full and collapse buckets 3 and 4 to counts plus their highest-severity three, noting the collapse. Do not collapse bucket 2 — an uncited "by design" is the thing most worth seeing.

### Step 8.5: Codex addendum (only when Codex landed late)

**Only reachable when Codex was launched with `CODEX_REASON: asked` on a normal-risk run.** A Codex-off run has no background task, and a high-risk run waits for Codex before the verdict, so neither enters this step.

When the background task reports completion after Step 8 has printed, compact it (Step 6) and post a short addendum — not a re-print of the whole review:

```
CODEX ADDENDUM (finished <duration>, after the verdict)
verdict impact: <unchanged | now COMMIT-WITH-FIXES | now DO-NOT-COMMIT>
new blockers: <n>   corroborates existing: <n>   noise: <n>
<blocker lines, if any>
```

Then update `$RUN_DIR/report.md` and set `codex.changed_verdict` in the run log. That field is what eventually answers "is Codex worth keeping" with evidence instead of a guess.

### Step 8.6: Hand the run to `/ship`

**Skip this step when the architecture gate did not clear** (`ARCH_GATE` is `rejected` or `pending`). No critic ran, so there is nothing to hand ship. Say `SHIP_GATE: n/a — architecture not approved`.

**Skip this step entirely in pr-remote mode.** The handoff arms a gate on *your* next `/ship` of *your* branch; logging someone else's PR into it would suppress findings on a branch you never reviewed. Say `SHIP_GATE: n/a — reviewed PR #<n>, not this branch` and move on.

**Run before Step 9** — it needs the checkpoint SHA, which the reset destroys.

Build the pass list from the passes that actually ran and returned `STATUS: ok`. Start from `lattice,cso` (dropping either that failed), and append `,codex` **only** when Codex was requested (`CODEX_REQUESTED: 1`) *and* returned `STATUS: ok`. Then:

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-handoff.sh" \
  "$RUN_DIR" "$STATUS" "$VERDICT" "$FR_PASSES" "$RUN_DIR/findings.json"
```

- `STATUS` is `clean` only when bucket 1 is empty; otherwise `issues_found`.
- The fourth argument is the comma list of **critic** passes that returned `STATUS: ok` — drop any that failed or were unavailable, **and never include `codex` on a Codex-off run** (it never launched, so it covered nothing), and never include `narrative`, `risk`, `static-analysis`, `architecture`, or `eng-review`. This is load-bearing, not bookkeeping: the ship-side gate only cuts ship's `testing`/`maintainability` specialists if `lattice` is in that list, and only cuts ship's Codex passes if `codex` is. Listing `codex` when it did not run would make ship **skip** its own Codex passes on the strength of a fresh-review pass that never happened — silently removing cross-model coverage from the final gate. The default (Codex-off) run must therefore hand ship `lattice,cso` and let ship run its own Codex. `narrative`, `risk`, and `architecture` report no findings, and `static-analysis` and `eng-review` map to no ship specialist — listing any of them would claim coverage that nothing produced.
- `findings.json` is a JSON array you write first. Rules for it:
  - **Only buckets 2, 3, and 4**, each as `action: "skipped"`. Those are the decisions worth carrying forward.
  - **Never log a bucket 1 (REAL BUG) finding.** Omitting it is deliberate: ship re-reviews it, which is the regression check on your fix. Logging it as `skipped` would suppress the one finding you most need re-verified.
  - `fingerprint` is exactly `path:line:category` — repo-relative path, the finding's line, the category slug lowercased. A wrong fingerprint simply fails to match and the finding resurfaces in ship. **This step fails safe in that direction**: the worst outcome is answering a review question twice, never a real bug being hidden.

This entry does two things downstream. Ship's **"Cross-review finding dedup"** step suppresses any finding whose fingerprint was logged with `action: "skipped"` on this branch, provided that file has not changed since the logged commit — that is findings-level, and it is consumed at ship's Step 9.3, *after* every specialist has already run. The dispatch-level saving is separate and comes from `references/ship-dispatch-gate.md`, which reads this same entry *before* Step 9 fans out.

(Ship's behaviors live in the external gstack install: `~/.claude/skills/ship/SKILL.md` and `~/.claude/skills/gstack/ship/sections/review-army.md`. Named by section rather than line number because line numbers drift on every `gstack-upgrade`.)

**When the handoff fails** — `SHIP_GATE: will_not_fire` — say so in chat, and say what it costs: ship will re-dispatch its full Step 9 army and re-ask about findings you already triaged. This handoff has silently no-op'd in past runs (one recorded run logged `handoff_rc: -1` and nobody noticed), so the failure is announced rather than left to be discovered at ship time. It is a convenience, never a gate: continue either way.

**What this does not do:** it does not flip the Eng Review row on ship's readiness dashboard. That row only reads entries from skills named `review` or `plan-eng-review`, and this skill logs as `fresh-review`. Ship will print "No prior eng review found — ship will run its own pre-landing review in Step 9" every time. That is correct and must not be routed around: the row tracks eng review of the **final** diff, which this skill deliberately does not review.

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

The index restore is gated on those two states **by name**, not on `≠ skipped`, and the difference only shows up in pr-remote mode: nothing was ever staged there, so a `read-tree` would restore an index snapshot the user never asked for and silently discard anything they staged while the review was running. That is a data-losing no-op with no output to notice it by — `INDEX: restored` looks exactly like success.

Everything is skipped when `CHECKPOINT=skipped` — nothing was staged, nothing was committed, nothing to undo.

Then tell the user: "Working tree restored — staged/unstaged split is back as it was." In pr-remote mode say instead: "Your tree was never touched; the PR checkout has been removed."

This must run even on abort or error. If the user interrupts mid-review, restoring the tree is the first thing you do on the next turn — `state.env` survives, so `fr-restore.sh "$RUN_DIR"` is all it takes.

### Step 10: Persist the run log

Write `$RUN_DIR/report.md` — and because chat is now lean, this file is where the **long form** goes: the Step 8 chat output, plus everything trimmed off it (the full narrative sections `NEW OR CHANGED RULES` / `BOUNDARIES AND CONTRACTS` / `NOT IN THIS CHANGE`, the Pass K risk rationale and factor line, the full pass inventory line, the UI-preview line, the structural "not covered here — /ship owns …" note, the PR-context and static-analysis summary, the scope, and the isolation-audit result). Nothing that used to be in chat is lost; it just lives here now. Then write `$RUN_DIR/run.json`:

```json
{"skill":"fresh-review","schema":9,"run_id":"<RUN_ID>",
 "ts_start":"<TS_START>","ts_end":"<now>","duration_s":0,
 "repo":"<repo>","branch":"<BRANCH>","base":"<BASE>",
 "mode":"<review|pr>","codex_requested":false,"codex_reason":"<none|asked|risk|risk-pass>",
 "architecture":{"gate":"<not_needed|approved|rejected|pending|skipped|failed>","decisions":0,"diagram":false},
 "pr":{"number":0,"url":"","state":"","head":"","drift":false},
 "pr_context":{"present":false,"comments":0,"reviews":0,"threads":0,"discussion_lines":0},
 "scope":"<REVIEW_SCOPE>","diff_base":"<DIFF_BASE>","checkpoint":"<CHECKPOINT_SHA>",
 "risk":"<RISK>","risk_level":"<low|med|high>",
 "static_analysis":{"present":false,"tool":"","total":0,"fixed":0,"suppressed":0,"dismissed":0,"unaddressed":0},
 "ui_preview":{"frontend":false,"reason":"<UI_REASON>"},
 "diff":{"files":0,"lines":0},
 "passes":[
   {"name":"architecture","status":"ok","duration_s":0,"arch_decisions":"<yes|no>","isolation":"clean"},
   {"name":"eng-review","status":"ok","duration_s":0,"findings":0,"isolation":"clean"},
   {"name":"lattice","status":"ok","duration_s":0,"findings":0,"isolation":"clean"},
   {"name":"cso","status":"ok","duration_s":0,"findings":0,"isolation":"clean"},
   {"name":"review","status":"ok","duration_s":0,"findings":0},
   {"name":"static-analysis","status":"ok","duration_s":0,"tool":"","unaddressed":0},
   {"name":"codex","status":"ok","duration_s":0,"findings":0,"changed_verdict":false},
   {"name":"risk","status":"ok","duration_s":0,"risk_level":"<low|med|high>","isolation":"clean"},
   {"name":"narrative","status":"ok","duration_s":0,"findings":0,"isolation":"clean",
    "vocab":"<ddd-principles|atom-defaults>","title_mismatch":false,"diagram":"<sequence|flowchart|none>"}],
 "triage":{"real_bug":0,"by_design":0,"noise":0,"misread":0,"deduped":0},
 "verdict":"<VERDICT>","handoff_rc":0,
 "tools":{"gstack":0,"codex":0,"gh":0}}
```

- **Set `architecture` from Step 4.8.** `gate` is `skipped` under `--arch-approved`, `failed` when Pass D failed, `not_needed` when Pass D found no decisions, and otherwise the `ARCH_GATE` answer. `decisions` is Pass D's count; `diagram` is whether one was shown. Omit the `architecture` pass when the gate was skipped, and the `eng-review` pass whenever Pass E did not launch (no decisions, gate skipped, or `HAS_GSTACK: 0`). When the gate did not clear, the implementation passes never launched — omit them too, and set `verdict` to `ARCH-PENDING` for a pending gate.
- Set `codex_requested` from the final `CODEX_REQUESTED` in `state.env` (after Step 4 and Step 6 may have forced it), and `codex_reason` from `CODEX_REASON`. It is what tells cross-run analysis apart: a `codex` pass absent because it was never asked for versus one dropped because it failed.
- **Omit the `codex` pass from `passes[]` when `codex_requested` is `false`** — a pass that never launched is not a pass that failed, and `codex_requested` already records the choice. When it was requested but failed or was unavailable, keep the entry with `"status":"failed"` so the failure stays visible.
- Omit `pr` outside pr-remote mode, and both the `narrative` and `risk` passes outside `pr` mode — an absent pass and a failed one must stay distinguishable. Likewise omit `risk_level` (top-level) and the `ui_preview` object outside `pr` mode; they are pr-mode artifacts. `risk` (the mechanical class) is always present.
- **Keep the mechanical `risk` and Pass K's `risk_level` distinct.** `risk` is `normal`/`high` from `fr-packet.sh`'s pattern count and gates `/cso` depth; `risk_level` is Pass K's `low`/`med`/`high` judgment and is what the header shows. In `review` mode `risk_level` is absent and only `risk` exists. When the `risk` pass failed, keep its entry with `"status":"failed"` and omit `risk_level`.
- **Omit the `review` pass from `passes[]` outside pr-remote**, and when `HAS_GSTACK: 0` in pr-remote (it could not run). Keep the entry with `"status":"failed"` only when it launched and failed — same rule as `codex`.
- **Omit the `static-analysis` pass and set `static_analysis.present:false` when `SA_PRESENT: 0`** — the PR raised no analyzer findings, or there was no PR, so the pass never launched. When it ran, fill `static_analysis` from Pass W's `TOOL` / `TOTAL` / `FIXED` / `SUPPRESSED` / `DISMISSED` / `UNADDRESSED` counts and keep the pass entry; keep it with `"status":"failed"` if it launched and failed. `unaddressed` is the count that became blockers.
- **Set `pr_context` from `fr-pr-context.sh`.** `present:false` when `PR_CONTEXT` was `none` or `unavailable`; otherwise fill `comments` / `reviews` / `threads` / `discussion_lines` from its keys. It records whether the producer had the PR's discussion to triage against, independent of whether any static-analysis pass ran.
- `ui_preview.frontend` is whether the diff touched UI (`fr-ui-detect.sh`'s `FRONTEND_HITS > 0`), and `reason` is the `UI_REASON`. Step 4.6 never launches, so there is no `shown`/`eligible` to record. `narrative.diagram` records which shape Pass N drew (`sequence`, `flowchart`, or `none`) — the direct measure of whether the diagram-first mode is producing diagrams or declining them.
- `tools.codex` stays availability (`HAS_CODEX`), independent of whether the run requested Codex.

Then:

```bash
. "$RUN_DIR/state.env"; FR_STATUS="$STATUS" bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-log.sh" "$RUN_DIR"
```

The script validates the JSON, appends it as one line to `$LOG_DIR/runs.jsonl`, prunes old run directories to `FR_RUN_RETENTION`, and pings the gstack timeline. Validation **gates** the append rather than following it: a malformed line in `runs.jsonl` breaks every future analysis of it. On `RUN_JSON: invalid`, `$RUN_DIR/run.json` is kept — tell the user the index entry was skipped, and why.

Fill the zeroed fields from the actual run — per-pass wall time, per-pass finding counts, and the triage bucket counts. Those are the point of the log, not decoration.

**What this log is for.** Three questions it is designed to answer across runs:

- *Where does the time actually go?* Per-pass `duration_s` replaces the impression that "the run is slow" with the name of the pass that is slow.
- *Is Codex earning its place?* Now that Codex is opt-in, the question is two-sided: `codex_requested` across runs shows how often anyone reaches for it, and `codex.duration_s` against `codex.changed_verdict` over the runs that did request it is the evidence for whether it pays off when they do.
- *Which pass produces noise?* A pass whose findings land overwhelmingly in buckets 3 and 4 is miscalibrated for this repo and should be re-scoped or dropped.
- *Is the narrative telling anyone anything?* `narrative.title_mismatch` over many pr-remote runs is the direct measure. If it is never true, the mode is producing pleasant restatements and its isolation is not buying what it costs; if it is often true, PR descriptions in this repo are not to be trusted, which is worth knowing on its own. `narrative.diagram` alongside it says whether the diagram-first mode is actually drawing diagrams or mostly returning `none`.
- *Does the risk class track reality?* `risk_level` against the triage counts over many runs answers whether the pass is calibrated: `high`-risk runs should not be the ones with zero real bugs *and* zero caution, and a repo where every change comes back `low` has a pass that has stopped discriminating.

**Schema history.** `schema:9` adds `codex_reason` (why Codex ran: the user asked, or high risk forced it — a `schema:8` `codex_requested:true` always means the user asked) and an `architecture` object (the gate's outcome, decision count, and whether a diagram was shown) and two optional passes, `architecture` (Pass D) and `eng-review` (Pass E). A run whose gate did not clear has neither the critic passes nor a normal verdict. Reading a `schema:8` entry, treat `architecture` as absent-unknown — the gate did not exist, and the implementation passes always ran. `schema:8` adds a `pr_context` object (whether the PR's description/discussion was gathered for triage, and its counts) and, for repos whose PR gate runs a static-analysis tool, a `static_analysis` object plus an optional `static-analysis` pass (Pass W) — present in any mode when the PR carried analyzer findings, absent otherwise. Reading a `schema:7` entry, treat `pr_context`, `static_analysis`, and the `static-analysis` pass as absent-unknown — none existed, and chat then carried the full narrative sections and coverage notes that `schema:8` moves to `report.md`. `schema:7` adds an optional `risk` pass (pr mode only), a top-level `risk_level` (Pass K's `low`/`med`/`high`, distinct from the always-present mechanical `risk`), a `ui_preview` object (pr mode only), and a `narrative.diagram` field. Reading a `schema:6` entry, treat `risk_level`, `ui_preview`, the `risk` pass, and `narrative.diagram` as absent-unknown — none existed, and the narrative then carried prose sections rather than a diagram. `schema:6` adds an optional `review` pass — present only on pr-remote runs where `HAS_GSTACK: 1`, carrying Pass R's findings from gstack `/review`. Do not confuse it with the `schema:2` `gstack` pass: both come from running `/review`, but the old one ran in *every* mode and this one is pr-remote only. Reading a `schema:5` entry, treat the `review` pass as absent-unknown — it did not exist, and pr-remote then covered nothing structural. `schema:5` adds `codex_requested` and makes the `codex` pass optional — absent when the run did not request Codex. Reading a `schema:4` entry, treat `codex_requested` as absent-unknown but assume `true`, since Codex ran unconditionally then and its pass will be present. `schema:4` adds `mode`, an optional `pr` object, and an optional fourth `narrative` pass. `schema:3` has three passes and no mode field — read its absence as `review`, since pr mode did not exist. `schema:2` entries carry a different fourth pass, `gstack`, from when this skill ran `/review` itself; a tool reading across versions must not treat either fourth pass's absence as a failure, and must not confuse the two — `gstack` reported findings, `narrative` never does. The shape is otherwise deliberately generic — `skill`, `run_id`, `duration_s`, `passes[]`, `verdict` — so a future cross-skill run-analysis tool can read it alongside other skills' logs without a per-skill parser.

## Failure modes and recovery

- **Checkpoint commit fails** (`CHECKPOINT: failed`) → no-checkpoint mode (Step 3), document it, and **still run `fr-restore.sh`** — `git add -A` already ran, so the index needs restoring even though there is no commit to reset.
- **Unmerged index** (`STOP_REASON: unmerged_index`) → stop at preflight. Resolve the conflict, then re-run.
- **A pass returns nothing / errors** → log it as skipped, drop it from the `passes` list in Step 8.6, and continue. No single pass is blocking, but the verdict must name the absent lens.
- **A pass ignores the compact return contract** and dumps prose → do not re-read it; note it in NOTES, extract findings from its `raw/` file with a compactor subagent as in Step 6.
- **Codex times out / fails** (only possible when `--codex` was requested) → verdict ships Claude-only, `CODEX_FAILED` in the log, the `codex` pass kept with `"status":"failed"`. Never substitute a Claude pass for it. Fix is `codex login` and re-run.
- **High-risk run without Codex** (`RISK: high` or Pass K `high`, and `HAS_CODEX: 0` or Codex failed) → a named gap, not a silent one. Print the high-risk reduced-coverage line (Step 8), keep the `codex` pass with `"status":"failed"`, and never substitute a Claude pass for it.
- **Codex not requested** (`CODEX_REQUESTED: 0`, the default) → not a failure. Pass C never launches, the pass line omits `codex`, and the run log records `codex_requested:false` with no `codex` pass. Mention once that `--codex` adds a cross-model pass if the user wants it; do not treat its absence as reduced coverage.
- **Subagent tries to fix code** → Step 6.5 catches it; `--revert` undoes it unless the checkpoint failed.
- **Pass R (review army) not run** → in pr-remote with `HAS_GSTACK: 0`, or when the pass errors, log it as skipped/failed, surface it in the `⚠ reduced coverage` chat line (Step 8), record the full unowned-gap note in `report.md`, and continue. The verdict must name the missing structural lens, never imply ship will catch it.
- **Pass R mutates the PR worktree** → its fix-first override should prevent any edit, but a mutation lands in `SOURCE_ROOT`, a disposable worktree deleted in Step 9, not your tree — so Step 6.5's user-tree check will not see it. If its NOTES report a fix was applied, treat its findings as reviewed against a modified tree and note it; the worktree is discarded regardless.
- **User aborts midway** → `fr-restore.sh "$RUN_DIR"` first, then report what was collected.
- **Forbidden read detected** → Step 6 handles it: note, downgrade confidence, optionally re-spawn. A Pass N leak is the exception — label the narrative contaminated or drop it, never print it clean.
- **`runs.jsonl` fails to validate** → the line is dropped, `$RUN_DIR/run.json` is kept, tell the user.
- **Handoff fails** (`SHIP_GATE: will_not_fire`) → continue, and tell the user ship will re-dispatch its full army and re-ask about triaged findings.
- **`PR: unresolved`** → stop, print `REASON` and its remedy from Step 1.5. Never fall back to reviewing the local branch: it would answer a question about PR #42 with a review of something else entirely.
- **Pass N returns prose instead of the block**, or returns file paths and function names → do not print it. Re-spawn once with the constraint list repeated; on a second failure print the review block alone and note `narrative ✗ format`. A narrative full of file paths is a diff summary, which the user can already get from `git diff --stat`.
- **Pass N invents a domain story for a tooling-only change** → print the review block alone and note it. This is the failure that makes the whole mode untrustworthy, so it is worth a `NOTES` line in the run log rather than a silent drop.
- **Pass N returns invalid Mermaid** (renders to an error, or is not a fenced `mermaid` block) → print the headline and text sections without the diagram, note `narrative ✗ diagram` in NOTES, and do not hand-fix the syntax with your own knowledge of the change — a diagram you drew is the author's-claim contamination the isolation exists to prevent. Re-spawn once if it is cheap; otherwise ship the text sections alone.
- **Pass K fails or is not returned** → the run is not blocked. Print the header risk as the mechanical class with ` (mechanical — risk pass failed)`, drop the `risk —` rationale and factor lines, keep the `risk` pass in the log with `"status":"failed"`, and continue. Risk is context for the verdict, never a gate on it.
- **UI presence check** → never an error and never a blocker. Step 4.6 runs `fr-ui-detect.sh` and prints one `UI preview — not shown: <UI_REASON>` line (`not pr mode`, `no frontend files in the diff`, or `app launching removed — …`). It launches nothing, so there is no capture to hang, fail, or wait on.
- **No PR for this branch** (`PR_CONTEXT: none`) → the normal default pre-commit case. PR-context triage and static-analysis verification simply do not apply; say nothing about them and run as before.
- **PR context unavailable** (`PR_CONTEXT: unavailable`) → `gh` is missing or a call failed (`REASON`). State it once — the discussion was not read and static-analysis follow-through was not verified — and continue. Never a blocker.
- **No static-analysis findings on the PR** (`SA_PRESENT: 0`) → Pass W does not run and this is not a gap. Do not print a `static analysis` line or a coverage caveat for it — there was nothing to verify.
- **Pass W returns UNADDRESSED findings** → each hits the static-analysis floor (Step 7) and is a blocker unless you cite the specific suppression or dismissal it missed. This is the intended path of feature 1, not a failure.
- **Pass W fails or errors** → log it with `"status":"failed"`, add `static-analysis follow-through not verified` to the reduced-coverage line, and continue. Its absence is a missing lens named in chat, never a silent pass.
- **Diagram rendered to an image** → print the image only (via `SendUserFile`), never the ` ```mermaid ` fence underneath it. Printing both is the duplication feature 3 removed; the fence is the fallback for when `mmdc` is unavailable or errors, and then it is printed *instead of* an image, not in addition.
- **Do not reintroduce app launching** → launching a review tree was removed in v0.9.0 because it is an RCE risk that cannot be gated: a review tree may be untrusted (a `--pr` fetch, or a fork/dependabot branch checked out locally and reviewed with `--mode pr`), and provenance is not mechanically decidable. Never add a launch path gated on `REVIEW_SCOPE`, filesystem location, worktree disposability, or git author metadata — none of those is a trust boundary. To view the UI, open the branch yourself.
- **PR head moves mid-review** (`HEAD_DRIFT: yes`) → not an error. Everything was reviewed at `PR_HEAD`; say so in the header and move on. Do not re-fetch — that would mix two commits' findings in one report.
- **PR worktree survives the run** (`WORKTREE: failed`) → tell the user the path and that `git worktree remove --force <path>` clears it. Do not leave it undisclosed; it is a full checkout's worth of disk.

- **Pass D finds architecture decisions** → the intended path. Show the diagram and trade-offs, run Pass E, ask (Step 4.8).
- **Pass D fails** → do not block. Print `⚠ architecture gate did not run`, go to Step 5, name it in the reduced-coverage line, log `architecture.gate: failed`.
- **Pass D returns invalid Mermaid** → print the decisions and trade-offs without a diagram, note `architecture ✗ diagram`, and still ask. Do not hand-fix it.
- **Pass E fails, or `HAS_GSTACK: 0`** → show the diagram and trade-offs and ask anyway. Say `ENG REVIEW — not run: <reason>` at the gate, keep the `eng-review` pass with `"status":"failed"` when it launched, and continue.
- **Pass E writes to the tree** → the gate's mutation check catches it before the question. Handle it as Step 6.5 does.
- **The user rejects the architecture** → not a failure. Triage Pass E's findings, verdict `DO-NOT-COMMIT` (pr-remote: `REQUEST-CHANGES`), skip the handoff, restore, log.
- **Step 5 reached with the gate closed** (`fr-arch-gate.sh` prints `ARCH_GATE: closed`) → launch nothing. Finish Step 4.8 (`not_decided`), or follow its rejected/pending branch.
- **No one can answer the gate** (AskUserQuestion unavailable or failed) → `ARCH_GATE=pending`. Never assume approval. Print the pending block, restore, log, and point to `--arch-approved`.
- **The session ends while the gate waits** → the checkpoint is still in place. On the next turn run `fr-restore.sh "$RUN_DIR"` first, as for any interrupted run, then ask whether to re-run with `--arch-approved`.

## What this skill does NOT do

- **Run gstack's `/review` — except in pr-remote.** On your own branch this is deliberate: `performance`, `data-migration`, `api-contract`, and Red Team are `/ship`'s to run on the final diff (see "Why gstack's `/review` is not a pass here"). Reviewing someone else's PR there is no ship of yours to run them, so pr-remote runs `/review` report-only as Pass R — the one place this skill does invoke it.
- **Open a literal fresh Claude Code session.** For maximum isolation before a major release: `git worktree add ../review-wt HEAD`, start Claude Code there, run the commands manually.
- **Auto-apply fixes.** The calling session applies fixes after triage. This skill only diagnoses.
- **Replace a full security audit.** `/cso --diff` covers the changed surface only. A full `/cso` remains a periodic job.
- **Replace QA.** Nothing here proves the code runs. `/qa` still applies.
- **Run the CI gates.** Tests, coverage, and lint are `/ship`'s job. A `COMMIT` verdict says the code reads correctly, not that it passes.
- **Stop `/ship` from reviewing again.** Ship's pre-landing review is unconditional and reviews the *final* diff — post-fix, post-CHANGELOG, post-base-merge — a different artifact from what these passes saw. `references/ship-dispatch-gate.md` trims the parts that are genuinely duplicated; the rest is supposed to run.
- **Analyze runs across sessions.** The log is written to be analyzable; reading it is a separate tool's job.
- **Post anything to GitHub.** The narrative and the risk class are printed to chat and written to disk, never sent. No `gh pr comment`, no `gh pr review`, no `gh pr edit --body`, no uploading a screenshot to the PR, not even in pr-remote mode where a PR is plainly sitting there — publishing a review under the user's name is theirs to decide, and an unattended run inside `/loop` must not be able to do it. If they want it posted, they will say so, and that is a separate action taken with the text in front of them. Reading the PR's description and discussion (Step 4.7) is read-only and one-directional: nothing is ever written back.
- **Feed PR context to the review passes.** The description, discussion, and bot findings gathered in Step 4.7 reach only the producer (triage) and Pass W. The critics and the narrator stay blind to them by design — that is the whole reason the gather writes to a producer-only directory the isolated passes are forbidden to read. If you find yourself handing `pr-context/` to Pass A, B, N, K, or R, you have broken the skill's central invariant.
- **Modify the PR under review.** pr-remote mode is read-only on someone else's branch. Findings are comments; the worktree is disposable and gets deleted.
- **Review a PR from another repo.** `foreign_repo` stops it. There is no local tree to materialize the head into, and a patch without its source tree produces reviewers reading the wrong file contents. Clone that repo and run there.
- **Persist a `/plan-eng-review` result.** Pass E skips its Review Log on purpose. Ship's Eng Review row tracks the *final* diff, and a pre-commit architecture review is not that.
- **Review implementation before the architecture is approved.** When Pass D finds design decisions, the implementation passes wait for the user's answer, and with no answer they do not run.
- **Replace reading the diff.** The narrative is at product altitude by construction — no paths, no names, no code. It tells you what changed and what it means; it cannot tell you whether line 84 is right. It is an orientation and a cross-check, not a substitute for review, which is exactly why this mode never ships it without one.

## Examples

**"fresh review my changes before I commit"** → the default run: Steps 1–10, `--codex` **not** passed; branch-scoped packet built once; Pass D checks for architecture decisions first and finds none; two isolated Claude subagents (lattice + `/cso`), no Codex; verdict and every finding printed to chat; tree restored; run logged. No questions asked — the architecture gate asks only when Pass D finds design decisions.

**"fresh review with codex"** / **"review my changes, cross-model too"** → `--codex`. Same run plus Pass C launched in the background alongside the two subagents; the run records the `codex` pass in `report.md`/`run.json`, and Step 8.5 posts an addendum in chat if it lands late. Everything else is identical to the default.

**"review this before I push"** with `auth/` in the diff → `fr-packet.sh` returns `RISK: high` on `PATH_HITS`; `/cso` upgrades to `--diff --comprehensive`, and Codex becomes a must (`CODEX_REASON: risk`) without the user asking. The verdict waits for Codex; the three sources are triaged under the security floor. Without `codex` on PATH, the verdict carries the high-risk reduced-coverage line.

**"fresh review, then ship"** → the default (Codex-off) run, nothing added. The handoff hands ship `lattice,cso`, so ship trims its `testing`/`maintainability` specialists but **runs its own Codex** on the final diff. Had the run used `--codex`, the handoff would add `codex` and ship would trim its Codex passes too.

**Codex still running when the Claude passes return** (a `--codex` run) → verdict prints as `codex ⧗ running`; the background task completes eight minutes later; Step 8.5 posts the addendum and records whether it moved the verdict.

**"pr review — what does this actually change?"** on your own branch → `--mode pr`. Same checkpoint, same packet, the two Claude critics, plus Pass N (diagram), Pass K (risk), Step 4.5's vocabulary resolution, Step 4.6's UI presence check, and Step 4.7's PR-context gather if the branch has an open PR — no Codex, since it was not requested and the diff is normal-risk. Chat gets the rendered graph, one short paragraph, then the verdict and every finding — nothing else; the risk class, the factor breakdown, and any UI note go to `report.md`. Handoff and restore run as normal, because this is still your branch.

**"review PR 42"** → `--pr 42`. Step 1.5 resolves it, fetches `pull/42/head`, and builds a detached worktree; Step 3 is skipped; Step 4.7 gathers PR #42's description and discussion into `pr-context/` (producer-only); the two critics, Pass N, and Pass K read the PR's diff blind and open files from the PR's tree, and — because no `/ship` of yours will ever review this PR — Pass R runs gstack `/review` report-only in that worktree, adding `performance`, `data-migration`, `api-contract`, and Red Team coverage (add `--codex` for this skill's own cross-model pass too). Chat gets the graph, one paragraph, the `APPROVE-WITH-COMMENTS` verdict, and the findings; the risk class and pass inventory go to `report.md`. Triage may cite a maintainer's decision from the thread for bucket 2, no handoff runs, and Step 9 deletes the worktree. Your own uncommitted work is untouched throughout — and nothing is posted to the PR.

**"review PR 42"** where the CI gate ran Wiz and left findings → same run, plus Step 4.7 reports `SA_PRESENT: yes  SA_TOOL: wiz`, so Pass W launches in Step 5. It reads the gathered Wiz findings and, for each, checks the PR diff and source: two were fixed, one carries a `wiz-ignore` with a reason, and one is still present with nobody having replied. Chat adds `static analysis (wiz): 4 raised — 2 fixed, 1 suppressed, 0 dismissed, 1 unaddressed`, and the one unaddressed finding appears as a BLOCKER under the static-analysis floor, pushing the verdict to `REQUEST-CHANGES`. Had all four been fixed, suppressed, or dismissed, the line would read `0 unaddressed` and no blocker would come from it.

**"review PR 42"** where the PR adds a checkout screen → Step 4.6 finds frontend files and records `UI preview — not shown: app launching removed — fresh-review does not launch a review tree (N frontend file(s) changed); open the branch yourself to view the UI` in `report.md` (it is no longer printed to the lean chat block). It does not launch the PR's app — that would run the author's code on your host — and it does not tell you to "just check it out locally," because a locally-checked-out PR is no more trusted than the fetched one. To view the UI, open the branch in an environment where you have judged it safe to run.

**"explain PR 42 for the standup"** with no `.lattice/standards/ddd-principles.md` → identical run, `VOCAB: atom-defaults`. The diagram and its annotations use generic domain terms and nouns lifted from the code's own naming, the report says so in one line, and the review still runs in full.

**A tooling-only PR** — CI workflow and lockfile → Pass N returns `HEADLINE: this change has no domain meaning; it is CI and dependency work`, `DIAGRAM: none`, every domain section `none`; Pass K returns `RISK_LEVEL: high` on the IaC/operational surface. That is the correct output, printed as-is — no invented diagram. `RISK: high` (mechanical) still fires on the IaC path, so `/cso` runs comprehensive over it, and Step 4.6 records `UI preview — not shown: no frontend files in the diff` to `report.md`.

**"fresh review"** on a branch that adds a new cache layer between the API and the database → Pass D returns `ARCH_DECISIONS: yes` with two decisions: a new cache component, and a new dependency from the API on it. The user sees a rendered Before/After diagram, pros (fewer DB reads) and cons (stale reads, a new failure mode when the cache is down), then Pass E's `/plan-eng-review` findings on the architecture. The skill asks. On `Approve`, the usual fan-out runs and Pass E's findings are triaged with the rest, tagged `eng-review`. On `Reject`, no implementation pass runs and the verdict is `DO-NOT-COMMIT`.

**"fresh review"** on a bug fix inside one module → Pass D returns `ARCH_DECISIONS: no`. One line in chat — `Architecture: no design decisions in this change — reviewing the implementation.` — and the run is otherwise unchanged. No question is asked.

**"fresh review, architecture approved"** → `--arch-approved`. Step 4.8 is skipped, and the run goes straight to the fan-out.

**The PR title says "add refund support"; the narrative says a fee is recorded but never reversed** → the `⚠` mismatch line in Step 8, `title_mismatch: true` in the run log. This is the outcome the whole isolation contract exists to make possible.
