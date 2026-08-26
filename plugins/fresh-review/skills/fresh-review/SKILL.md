---
name: fresh-review
description: |
  Pre-commit fresh-eyes code review. Orchestrates a context-isolated review pass that approximates what
  a new reviewer would catch — runs the lattice review and the gstack security audit against one shared
  diff packet, via subagents that cannot read design docs, intent, or prior session context. A
  cross-model Codex pass is available on request and off by default: it runs only when the invocation
  asks for it ("with codex", "cross-model review", "codex pass"). Triages findings against the
  producer-context, prints the verdict and every finding to chat, and logs the run for later analysis.

  Deliberately does NOT run gstack's `/review`. That skill is what `/ship` runs unconditionally at its
  own Step 9, on the final diff; running it here too pays for the same specialist army twice. This
  skill covers craft and security ground — plus cross-model ground when Codex is requested; `/ship`
  covers the structural specialists.

  Use when the user asks to "fresh review", "fresh-eyes review", "review my changes", "pre-commit
  review", "review before commit", "review with no bias", "independent review", "what did I miss",
  "check my work before I commit", "context-free review", or "review with fresh eyes". Proactively
  suggest before any /ship, /land-and-deploy, or manual git commit when the diff exceeds ~50 lines or
  touches auth, payments, migrations, or security-sensitive code.

  Has a second mode — **pr review** — that adds a plain-English account of what the change does,
  written in the repo's own domain vocabulary rather than in code. Use it when the user asks for a
  "pr review", "review this PR", "explain this PR", "what does this PR do", "what does this change
  do", "summarize this change/PR", "explain my changes in plain English", "describe this PR for a
  non-engineer", "write the PR description", or names a PR by number or URL ("review PR 42",
  "look at github.com/o/r/pull/42"). That mode reviews *and* narrates: it is the default run plus a
  narrator pass, never a summary in place of a review.

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
---

# fresh-review

Code review with enforced producer/reviewer context separation — pre-commit by default, or as a PR review that also explains the change in plain English.

## Why this skill exists

When you design, write, and review code in the same session, the reviewer-Claude already agrees with the design choices and knows the rationale. It rationalizes away its own decisions. Real review needs the reviewer to *lack* context the producer has. This skill enforces that separation by spawning subagents with strict context restrictions, optionally adding a genuinely out-of-process cross-model reviewer when the run asks for one, and then triaging their findings back in the producer context (where intent is known and "by design" can be properly justified).

The same separation turns out to be worth even more for *describing* a change than for finding fault in it. A summary written by someone who knows what the change was meant to do is a restatement of that intention; a summary built from the code alone is the only kind that can contradict it. That is what `pr` mode is for.

## Modes

Two output shapes, one machine. Every mode fans out the same critic passes against the same packet; a mode changes what *else* is produced and who the reader is. The critic passes are lattice and `/cso` always, plus Codex only when the invocation asked for it (see "The Codex opt-in" below).

| The user's words | Preflight flags | Subject of the review | Chat output |
|---|---|---|---|
| "fresh review", "review before I commit", "what did I miss" | *(none)* | your branch | verdict + findings |
| "pr review", "explain this PR", "what does this change do", "write the PR description" | `--mode pr` | your branch | **narrative** + verdict + findings |
| "review PR 42", a `github.com/…/pull/42` URL | `--pr 42` | PR 42's head commit | **narrative** + verdict + findings |

Resolve the mode once, from the invocation, and pass it to `fr-preflight.sh`. Do not re-derive it later.

- A **number or pull URL** anywhere in the request means `--pr <that>` — which implies `--mode pr`.
- Any plain-English *"what does this do"* framing means `--mode pr` with no PR ref: same branch, same passes, plus the narrative.
- Everything else is the default. When in doubt, default. The narrative is additive, so guessing `review` costs the user a paragraph; guessing `pr` on a plain pre-commit check costs a subagent.

### The Codex opt-in

**Codex (Pass C) is off by default and runs only when the invocation asks for it.** It is a separate `--codex` flag, orthogonal to `--mode` and `--pr` — add it to *any* of the three rows above. Resolve it once, from the invocation, alongside the mode:

- Pass `--codex` when the request names Codex or asks for cross-model coverage: "with codex", "codex pass", "cross-model review", "run codex too", "add a second model", "include the cross-model reviewer".
- Otherwise **omit it** — a plain "fresh review", "pr review", or "review PR 42" gets the two Claude critics (lattice + `/cso`) and no Codex. Do not add it because a diff looks risky, large, or security-sensitive: risk gates `/cso`'s depth (Step 4), never Codex. The user asks or it does not run.
- The flag is a request, not a guarantee: Pass C runs only when `--codex` was passed **and** `HAS_CODEX: 1`. If `--codex` was asked for but `codex` is not on PATH, say so (Step 1) — same as any other missing tool.

Everything downstream keys off `CODEX_REQUESTED` from `state.env`: Step 5 launches Pass C only when it is `1`, and the pass line, triage convergence, handoff, and log all treat an un-requested Codex as simply absent — distinct from a requested one that failed.

**`pr` mode adds Pass N — the narrator.** Its product is a plain-English account of what the change does, at the altitude of someone who owns the product and does not read code, in the vocabulary the repo's own DDD principles establish. It runs *alongside* the critics, never instead of them: a summary that has not been reviewed is how a change gets waved through on the strength of a good description.

### pr-local and pr-remote

`--pr <ref>` moves the subject of the review off your branch, and four things follow from no longer being the author:

| | `review` / `pr` on your branch | `pr` with a ref (**pr-remote**) |
|---|---|---|
| What is reviewed | merge-base..worktree | the PR head, fetched fresh |
| Source files opened from | your checkout | a detached worktree at the PR head (`SOURCE_ROOT`) |
| WIP checkpoint (Step 3) | runs | **skipped** — nothing of yours is being reviewed |
| Verdict vocabulary | `COMMIT` / `COMMIT-WITH-FIXES` / `DO-NOT-COMMIT` | `APPROVE` / `APPROVE-WITH-COMMENTS` / `REQUEST-CHANGES` |
| Triage bucket 2 ("by design") | may cite this session's decisions | **may not** — you have no intent knowledge |
| Handoff to `/ship` (Step 8.6) | runs | **skipped** — you are not shipping this |

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
- **Codex is opt-in.** When requested (`--codex`, see "The Codex opt-in") it runs as a full pass, in the background, concurrent with the others. When not requested it does not run at all, and the run has two critic passes rather than three. Rationale for the background invocation is in Pass C.

## Why gstack's `/review` is not a pass here

`/review` is the exact skill `/ship` runs at its own Step 9 — unconditionally, with no "already reviewed?" gate on dispatch. Its only filters are a `DIFF_LINES < 50` floor, scope detection, and an adaptive gate that needs 10+ dispatches at zero findings before it ever fires. `skip_eng_review` does not help: it flips one row on ship's readiness dashboard and ship then says outright to continue without blocking, because it runs its own review in Step 9 regardless.

So a fresh-review that ran `/review` and was then followed by `/ship` paid for the same seven specialists, Red Team, and adversarial subagent twice — and worse, ship's Step 9 stops for fixes and asks for a re-run, so the full army re-dispatches on every fix cycle.

The division of labor is therefore fixed, not configurable:

| | fresh-review (this skill) | `/ship` Step 9 / Step 11 |
|---|---|---|
| Craft and standards conformance | Pass A (lattice) | — |
| Security | Pass B (`/cso`, confidence-gated) | `security` specialist (ungated) |
| Cross-model review | Pass C (`codex review`) — **only when `--codex` is requested** | Codex structured + adversarial |
| performance, data-migration, api-contract, Red Team | **not covered** | owned here |
| Plain-English account of the change | `pr` mode, Pass N | — |
| Reviews which artifact | the pre-commit checkpoint, or a PR head | the final diff, post-fix, post-base-merge |

The four structural specialists and Red Team are genuinely absent from this skill. That is the trade: they run once, at ship time, against the diff that actually lands. If you want them *before* commit, the answer is `/review` directly, not this skill.

The reverse redundancy — ship re-running what *this* skill already did — is handled from the ship side by `references/ship-dispatch-gate.md`.

## Output contract

Two audiences, two artifacts. Do not confuse them.

- **Chat is for the human.** It gets the verdict on the first line and *every* finding from *every* pass, merged and triaged — plus, in `pr` mode, the narrative in full above it. It is never a pointer to a file. "Full report at `<path>`" is not an acceptable substitute for the findings themselves, and it is not one for the narrative either: in `pr` mode the narrative *is* what the user asked for.
- **Disk is for the agents and for later analysis.** Raw pass reports, the diff packet, and the run log live in the run directory. Nothing there is required reading for the user.
- **Nothing is for GitHub.** No mode posts, comments, or edits a PR. See "What this skill does NOT do".

## Token discipline

Four invariants. Every step below is built around them; violating one silently makes the run cost several times what it should.

1. **The orchestrator never loads the diff** — nor the DDD principles document. `fr-packet.sh` classifies risk with `grep -c` over the patch and prints only counts; `fr-ddd-vocab.sh` extracts the vocabulary sections into a brief and prints only its line count. A full refiner output runs to a thousand lines, and the orchestrator's job is to hand it to Pass N by path, not to read it.
2. **Reviewers read the packet, not git.** The diff is materialized once (Step 4) and every pass is handed the same file paths. No pass re-derives scope, and no pass runs `git diff` — which also guarantees their findings are comparable.
3. **Passes return compact findings; prose goes to disk.** This is the largest saving by far. `/cso` alone emits thirteen numbered phases of narrative; the compact block is a few hundred tokens. Each pass writes its full report to `$RUN_DIR/raw/` and returns only the fixed-format block in Step 5.
4. **Raw reports are not read back.** Triage runs on the compact blocks. Open a raw report only to disambiguate one specific finding, and read only that finding's section.

The same principle governs the shell work: every mechanical step is a script in `${CLAUDE_PLUGIN_ROOT}/scripts/` that prints a small delimited key block. Read the block, not the machinery. Do not reimplement a script's logic inline — the scripts are where the gating rules are actually enforced, and a hand-typed variant of one is how those rules get lost.

## Workflow

Steps run in order. Step 5 is one parallel fan-out; everything else is sequential. Four steps are mode-conditional and say so in their own heading: **1.5** and **4.5** only run in the modes that need them, and **3** and **8.6** are skipped in pr-remote. Nothing else branches on mode.

Every script takes `$RUN_DIR` and reads the rest of its inputs from `$RUN_DIR/state.env`, which `fr-preflight.sh` creates and later scripts append to. You never have to thread variables between Bash calls by hand — and because state lives on disk, a run interrupted mid-way can still be restored on the next turn.

### Step 1: Preflight

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh"                   # review mode
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh" --mode pr          # pr mode, your branch
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh" --pr 42            # pr-remote (implies --mode pr)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh" --codex            # review mode + Codex (Pass C)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh" --pr 42 --codex    # pr-remote + Codex
```

This probes the repo, resolves the review scope, creates the run directory, and writes `state.env`. Export `RUN_DIR` from its output — every later script takes it as `$1`. Pass the flags from the Modes table verbatim, and add `--codex` only when the invocation asked for it (see "The Codex opt-in"); the script rejects an unknown flag or mode with a non-zero exit rather than falling back to a default, because a silently-defaulted `--pr` would review the local branch under someone else's PR number.

On `STATUS: stop`, tell the user and stop. `STOP_REASON` is one of:

- `not_a_repo` — nothing to do here.
- `nothing_to_review` — no dirt and no commits the base branch lacks.
- `unmerged_index` — a conflict is in progress. Do **not** checkpoint a conflicted tree; a half-merged tree is not a reviewable diff. Resolve it, then re-run.

**Neither of the last two can fire under `--pr`,** and that is deliberate: both describe the *local* tree, which is not the subject of a pr-remote review. A clean checkout on `main` is the normal state to review someone else's PR from, and `nothing_to_review` there would stop the run with a message that reads exactly like a correct answer. A conflicted index is likewise harmless in that mode — it is never staged, committed, or restored.

`AHEAD` counts commits **not in the base branch** (`$DIFF_BASE..HEAD`) — deliberately not `@{upstream}..HEAD`. Comparing a branch against its own upstream asks the wrong question: a fully pushed PR branch reports `AHEAD=0` even though its PR diff is a hundred commits wide, and a branch with no upstream falls back to `0`. Either would stop the skill with "nothing to review" while a complete, reviewable diff sits in front of it. The `@{upstream}` form survives only as the degraded fallback for when there is no `origin/$BASE` to merge-base against.

Tool-availability accounting — state each of these up front, never silently:

- `HAS_GSTACK: 0` → `/cso` does not exist here. **A critic pass cannot run.** Say so plainly, run Pass A (and Pass C if it was requested and available), label the verdict reduced-lens. Discovering this inside a subagent instead wastes the run and produces a report that looks complete but isn't. Note also that no gstack install means no `/ship` either, so the structural specialists this skill defers to will never run at all.
- `CODEX_REQUESTED: 0` → the run did not ask for Codex; Pass C does not run and is absent by choice, not by failure. This is the default. Do not mention missing cross-model coverage as a gap — it was not requested. Only note, once, that `--codex` is available if the user wants a second model.
- `CODEX_REQUESTED: 1` with `HAS_CODEX: 0` → Codex was asked for but `codex` is not on PATH, so Pass C **cannot** run. Say so plainly, run the Claude critics, label the verdict reduced-lens, and do not substitute a Claude pass for it. Fix is `codex login` (or installing the CLI) and re-run.
- `CODEX_REQUESTED: 1` with `HAS_CODEX: 1` → Pass C runs (Step 5).
- `HAS_GH: 0` → pr-remote is impossible. Only matters when a PR ref was given; Step 1.5 stops on it.
- `CODEX_CFG: unknown` → `gstack-config` was not found, so the setting could not be read. Report unknown, never guess `enabled`. This setting gates *gstack's* internal Codex, not ours; Pass C runs on `CODEX_REQUESTED` and `HAS_CODEX`, never on this.

Two other outputs matter later:

- `DIRTY: 0` with `AHEAD > 0` → the branch carries commits the base does not, pushed or not. Review them: the checkpoint self-skips in Step 3, scope stays `branch`. This is the normal shape of an open PR whose work is fully committed and pushed.
- `INDEX_TREE` is a real tree object written from the pre-review index, so it carries the staged *content* of every path, not just its name. Step 9 restores from it **exactly**. A name list cannot do this: a partially staged file — some hunks in the index, others not — restores by re-staging the whole file, silently folding the unstaged hunks in and destroying the split the user built.

The run directory persists, unlike a `mktemp` scratch dir — it is the record that makes a run analyzable afterward. It lives under `.fresh-review/` when that path is already gitignored, and under the git dir otherwise. The script never appends to `.gitignore`: mutating a tracked file mid-review would inject a change into the diff under review.

`LOG_DIR` is deliberately the **common** git dir, not the per-worktree one. In a worktree `git rev-parse --git-dir` resolves to `.git/worktrees/<name>`, so an index written there would fragment across worktrees and be deleted with them — and cross-run analysis would silently see only a fraction of the history. Run directories stay local and disposable; the index in `LOG_DIR` is the durable record. Entries may therefore outlive the run directory they point at, which is expected.

### Step 1.5: Resolve the PR (pr-remote only)

Skip entirely unless `PR_REF` is set.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-pr-resolve.sh" "$RUN_DIR"
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

**The PR title is fetched and deliberately withheld from every pass.** It is in `$RUN_DIR/pr.json`, and it goes in the Step 8 header for the human to read — but never into the packet or a subagent prompt. The title is the author's claim about the change; Pass N's entire value is deriving the change from the code independently, and a divergence between the two is a finding rather than an input. The body is never fetched at all.

### Step 2: State the scope

`fr-preflight.sh` already printed `REVIEW_SCOPE` and `DIFF_CMD`. Say them out loud — one canonical scope string, handed identically to every reviewer so their findings are comparable. Nothing is materialized yet; the packet is built in Step 4, after the checkpoint, so that untracked files are in it.

State `SOURCE_ROOT` too whenever it is not the repo root. It is the one piece of scope a reviewer can get wrong silently: reading the right path in the wrong tree returns plausible file contents from the wrong commit.

### Step 3: WIP checkpoint

**Skip this step entirely in pr-remote mode** — `CHECKPOINT` is already `pr_remote`, the diff comes from two committed refs, and there is nothing of yours under review. Committing the user's unrelated work-in-progress in order to review someone else's PR would be a mutation with no purpose.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-checkpoint.sh" "$RUN_DIR"
```

Commits everything with `--no-verify` (this skill IS the review), or self-skips when the tree is already clean. `CHECKPOINT` comes back as exactly one of `committed`, `skipped`, `failed` — never empty, because three later steps branch on it and an unset value fails *silently* rather than loudly. `CHECKPOINT_SHA` is always set.

**What the checkpoint is for:** making untracked files visible. A brand-new file does not appear in `git diff` at all, so without staging it the reviewers would never see the code most likely to contain fresh bugs. It also pins a stable SHA for the audit trail and for Codex's `--commit` scoping. It does not freeze what reviewers read — they read the packet, which is why the packet is built after this point and not before.

`CHECKPOINT` and `INDEX_TREE` stay distinct because the two undos in Step 9 are independent. `git add -A` mutates the index whether or not the commit that follows succeeds; a "no checkpoint, so skip the restore" rule would leave the user's carefully split index fully staged.

On `CHECKPOINT: failed`, continue in no-checkpoint mode: the packet builds from `git diff HEAD` / `git diff $DIFF_BASE`, untracked files go unreviewed (record that in the report), and the script has already written `raw/pre-fanout.status` as the baseline the Step 6.5 mutation check needs. **Step 9's index restore still runs** — only the commit-reset half is skipped.

**Do not edit anything from here until Step 9 completes.** A formatter-on-save or codegen watcher firing mid-review produces findings with stale line numbers.

### Step 4: Build the shared diff packet and classify risk

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-packet.sh" "$RUN_DIR"
```

Materializes the scope **once** into `$RUN_DIR/packet/` — `diff.patch`, `stat.txt`, `files.txt`, `scope.txt` — and classifies risk by pattern count over the patch, so the orchestrator sees integers rather than a diff. Every reviewer is handed these exact paths.

`RISK: high` fires on any auth/payment/migration/secret path hit, any IaC file, more than three body hits, or more than 300 changed lines. It gates exactly one thing:

| | normal | high-risk |
|---|---|---|
| `/cso` scope | `--diff` | `--diff --comprehensive` (2/10 bar, more surfaced) |

Codex depth is deliberately *not* gated on risk. Whether Codex runs at all is decided by `--codex` at invocation, never by risk — a high-risk diff does not conscript Codex, and a requested Codex runs its structured review regardless of risk class. Since Pass C is off the critical path, there is nothing to save by varying its depth.

State the file count and risk class out loud. If `LINES` exceeds ~2000, warn that reviewer quality degrades at that size and that a re-run scoped to a subdirectory reads more carefully — then **proceed anyway**. This skill never blocks on a question: it is meant to run unattended, including inside `/loop`. Every branch point resolves to a default and says which default it took.

### Step 4.5: Resolve the domain vocabulary (pr mode only)

Skip unless `MODE` is `pr`.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-ddd-vocab.sh" "$RUN_DIR"
```

Decides which vocabulary Pass N speaks in and materializes it as `packet/ddd.md`. Resolution order is the ddd-refiner's output first, tactical defaults second:

| `VOCAB` | Source | What Pass N can claim |
|---|---|---|
| `ddd-principles` | `.lattice/standards/ddd-principles.md` under `SOURCE_ROOT` | the repo's real ubiquitous language |
| `atom-defaults` | no document — generic tactical terms + nouns inferred from the diff | structural terms only |

`GLOSSARY` refines the first row: `extracted` means the document has glossary, bounded-context, or invariant sections and only those were passed through; `headings_only` means it has none and its heading list was used instead, since the section names still carry the domain's nouns. `DDD_MODE` (`overlay` / `override`) tells Pass N whether generic DDD terms are still in play alongside the document's.

**State `VOCAB` in the Step 8 output, always.** A narrative written in the repo's own language and one written in textbook DDD terms read almost identically and are worth very different amounts — the reader has to be told which one they got, for the same reason `HAS_GSTACK: 0` is stated rather than quietly absorbed. This is also the cheapest possible nudge toward running `/lattice:ddd-refiner`: `atom-defaults` on a repo with a real domain is a gap worth naming once, in passing, without turning the report into a pitch.

Read the printed keys, not the brief. The brief exists to be handed to Pass N by path.

### Step 5: Fan out all reviewers (one parallel batch)

Launch the Claude subagents **in a single message** — two subagents in `review` mode, three in `pr` mode — **and, only when `CODEX_REQUESTED: 1`, the Codex background command in the same message.** When Codex was not requested there is no Pass C to launch; the fan-out is Claude-only and everything downstream treats Codex as absent. Codex overlapping the others is the entire reason it stopped being a latency problem, and Pass N is cheap enough that adding it changes wall time by roughly nothing.

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
> **Forbidden reads** — do not open these even if they look relevant, *and do not open them because a skill you invoke tells you to*: `.lattice/requirements/**`, `.lattice/context/**`, `.lattice/contexts/**`, `.lattice/reviews/**`, `*.plan.md`, `*.design.md`, `docs/decisions/**`, `TODOS.md`, `ONBOARDING.md`, anything under `~/.gstack/projects/**`, and any file whose purpose is to record intent rather than behavior. **Forbidden commands**: `gh pr view`, `gh issue view`, `gh pr diff --body`, `git log`. Allowed: `.lattice/standards/**`, `.lattice/learnings/**`, `.lattice/config.yaml`, `AGENTS.md`/`CLAUDE.md`, and the diffed source. (Learnings are repo-wide rules, not this change's intent — read them, never write them.)
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

Each of these commands is a full interactive workflow that ends in *acting*, not merely reporting: `/cso` ends in a remediation conversation, `/lattice:review` ends by writing to a tracked file. A generic "be non-interactive and read-only" in the isolation contract does not reliably beat a nested skill's own numbered steps — the subagent is reading that skill as executable instructions, and the last instruction it reads wins. So each pass below names the specific sub-steps to skip, *by their heading*, and Step 6.5 verifies the outcome mechanically rather than trusting the prompt. Both are needed: the prompt sets intent, the check catches the miss.

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

> Your job is not to find defects — three other passes are doing that, and a defect you notice is theirs to report, not yours. Your job is to say what this change **does**, in plain English, in this repo's own domain language.
>
> Read `{{RUN_DIR}}/packet/ddd.md` first — it is this repo's domain vocabulary, and `VOCAB` there tells you whether it is the project's real ubiquitous language or generic tactical terms. Then read `diff.patch`. Open a source file from `{{SOURCE_ROOT}}` only to learn what a thing *is* when the diff does not make that clear.
>
> **How you must write.** These are not style preferences; a narrative that breaks them is worse than no narrative, because it reads authoritative while saying nothing:
>
> - **No code, no file paths, no line numbers, no diff excerpts, no function or variable names.** One exception: a name that is *itself* a term in the domain vocabulary. `Order` may appear. `OrderServiceImpl`, `handleSubmit`, and `src/api/orders.ts` may not.
> - **No empty verbs.** "Refactored", "updated", "improved", "enhanced", "cleaned up", "various changes", "better error handling" all say nothing. Say what is now true that was not true before.
> - Present tense, active voice, one idea per line. At most six bullets in any section — if a section needs more, you are describing code rather than the domain, so raise the altitude.
> - **Never state what the author intended.** You have not been shown it and you are not permitted to look. Describe what the code now does. "This aims to…" and "the goal is…" are both out of bounds; "a customer can now…" is what you are for.
> - **If the change has no domain meaning, say exactly that.** Tooling, CI, build config, formatting, dependency bumps, and test-only changes are real work with no domain story. Put that in HEADLINE and leave the domain sections at `none`. Inventing a domain narrative for a build change is the single worst outcome available to you — it is the failure that makes every future narrative untrustworthy.
>
> Write your full narrative to `{{RUN_DIR}}/raw/narrative.md`. Return *only* this block:
>
> ```
> PASS: narrative
> STATUS: ok | partial | failed
> VOCAB_USED: <terms from the brief you actually used, comma-separated; empty if none applied>
> ---
> HEADLINE: <one or two sentences — what this change makes true or possible>
> ---
> WHAT CHANGED
> - <domain thing>: <what is now different about it>
> ---
> NEW OR CHANGED RULES
> - <a condition the system now guarantees, or has stopped guaranteeing — or "none">
> ---
> LIFECYCLE AND FLOW
> - <a new or removed step, state, or event in a flow — or "none">
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
- **Still running past `CODEX_JOIN_BUDGET`** → proceed without it. The verdict ships labeled Claude-only, and when the background task exits you post the addendum (Step 8.5). Nothing is killed; the work completes and lands on disk either way.

Then audit isolation. Check each `FILES_READ:` line against the forbidden list.

- Clean → proceed.
- Forbidden path present → note the leak, downgrade that pass's confidence (its *"by design"* concessions become suspect; its bug findings do not). Re-spawn only if the leak is material and the pass is cheap.
- `FILES_READ:` missing → unverified isolation. Note it, proceed. Do not re-run on this alone.

Self-reporting is the only audit available for *reads* — a parent agent cannot inspect a subagent's tool trace, and it cannot see a `gh pr view` call at all. Treat this as a smoke detector, not a guarantee. (Step 6.5 is the one part of the contract that *is* mechanically verified; reads are not.)

No remaining Claude pass natively hunts for intent — that was `/review`'s habit, and `/review` no longer runs here. So a forbidden read from Pass A, Pass B, or the compactor is genuinely anomalous rather than expected, and deserves more weight than a routine leak: investigate it instead of noting it and moving on.

**A forbidden read by Pass N is worse than any other pass's,** and is the one leak that should make you discard output rather than downgrade it. A critic that peeked at a design doc produces findings that are still findings. A narrator that peeked at a plan, a commit message, or a PR title produces a narrative that has quietly become a *restatement of the author's claim* — indistinguishable in form from an independent reading, and it destroys the only property that made the narrative worth printing. On a Pass N leak: label the narrative `[intent-contaminated]` in the Step 8 output, or re-spawn it. Never print it clean.

### Step 6.5: Reviewer mutation check (read-only enforcement)

The prompt asked the reviewers not to write. This verifies it, because a subagent inherits the parent's tool access — there is no per-call tool restriction to lean on.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-mutation-check.sh" "$RUN_DIR"
```

`LEAK: none` → proceed. `LEAK: detected` → re-run with `--revert` to quarantine and restore:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-mutation-check.sh" "$RUN_DIR" --revert
```

The script picks its own baseline from `CHECKPOINT`, and that distinction is the whole reason it is a script and not an inline `git status`:

- `committed` and `skipped` both leave a clean tree at fan-out, so *any* dirt now came from a reviewer — the strongest form of this check. Revert is safe: tracked files go back to `HEAD`, which holds the pre-review content either way.
- `failed` has the producer's own uncommitted work interleaved with the reviewer's, and `git restore` cannot tell them apart. The script **refuses `--revert`** there and reports `REVERT: refused_checkpoint_failed`. Print the delta, name the suspect paths, hand it to the user.
- `pr_remote` is the `failed` case's shape for a different reason: nothing was ever staged, so the user's untouched work-in-progress is still sitting in the tree. A raw status here would report all of it as a reviewer leak on every single run, so the check is a baseline diff, and `--revert` is refused (`REVERT: refused_pr_remote`) for the same reason it is under `failed`.

In pr-remote mode there is a **second** tree a reviewer could have written into, and it is the one they were pointed at, so `PR_WT_LEAK` reports it separately. Dirt there counts as a leak even though it needs no revert — Step 9 deletes the worktree regardless. What matters is the inference, not the cleanup: a reviewer that ignored "do not fix" may equally have ignored the forbidden-reads list.

**Untracked files are only listed, never cleaned.** `git clean` here could delete real work — a build artifact, a watcher's output, or a file the user created a second ago. Report `UNTRACKED_REMAINING` and let them decide.

Record any violation, and treat that pass's findings as still valid but its judgment as suspect: a reviewer that ignored "do not fix" may have ignored the forbidden-reads list too.

### Step 7: Triage

You are back in the producer context with full knowledge of design intent. Work from the compact blocks — Pass N's is not among them; it carries no findings and never enters triage. Deduplicate across passes (same `file:line` + same root cause = one finding, sources merged), then assign each to exactly one bucket:

1. **REAL BUG** — must fix before commit. State the fix in one sentence.
2. **REAL BUT BY DESIGN** — cite the specific decision from this session, or the specific standard/doc, that makes it intentional. No citation → reclassify as REAL BUG. Non-negotiable: this is what stops the producer from rationalizing.
3. **STYLISTIC / NOISE** — one sentence on why it doesn't matter here.
4. **REVIEWER MISUNDERSTOOD** — what they got wrong. Use sparingly; bias hard against this bucket. It is the escape hatch the producer-Claude reaches for.

Two overrides:

- **Security floor**: a `cso` finding at HIGH or CRITICAL cannot go to bucket 3 or 4 without naming the specific compensating control — the code path, config, or middleware that neutralizes it — and where it lives. Absent that, it is a REAL BUG.
- **Convergence**: a finding raised by two or more passes cannot go to bucket 3 — but weight the convergence by how independent the sources actually are, because not all agreement is evidence:

  | Sources agreeing | Independence | Weight |
  |---|---|---|
  | `codex` + `lattice`, or `codex` + `cso` | different model family, separate process, no shared context | **strongest** — treat as near-confirmed; bucket 2 needs an explicit citation |
  | `cso` + `lattice` | same model, but different checklists and a confidence gate on one side | moderate |

  The two `codex` rows exist only when Codex ran — i.e. `--codex` was requested and it succeeded. **On a default (Codex-off) run the only convergence available is `cso` + `lattice`, the moderate row**, and that is expected, not a defect. Do not manufacture cross-model agreement that no pass produced.

  With only two or three critic passes, convergence is *rarer* than it would be with a nested specialist army — but not *weaker*. The rows above keep exactly the weight they state, and a finding raised by one pass alone is still a finding raised by one pass alone. Do not loosen bucket 2's citation requirement, or relax the security floor, to compensate for thinner agreement: the correct response to fewer lenses — including a run that opted out of Codex — is a more conservative verdict, not a lower bar.

**In pr-remote mode there is no producer context, and the buckets change accordingly.** This is the one step where the mode genuinely alters your reasoning rather than your output format:

- **Bucket 2 may not cite a session decision** — there were none; the author is someone else. It admits only a standard, a config, or a code path you can point at in `SOURCE_ROOT`. "The author presumably meant to…" is bucket 1. This is stricter than the normal rule, not looser: the usual escape hatch was legitimate only because the producer actually held the intent.
- **Bucket 4 requires that you opened the file.** Claiming a reviewer misread code you have not read yourself, in a change you did not write, is a guess. Without the read, it stays in bucket 1.
- **The verdict vocabulary is `APPROVE` / `APPROVE-WITH-COMMENTS` / `REQUEST-CHANGES`.** Bucket 1 non-empty means `REQUEST-CHANGES`.
- Findings are **comments, not fixes.** Phrase the `→ fix:` line as what you would ask for, and never edit the PR's code.

Write the merged pre-triage findings to `$RUN_DIR/findings.tsv` for the log.

### Step 8: Report to chat

**This is the primary output.** Print it in full, in chat, in this shape. Verdict first, always.

In `pr` mode, one block comes before the verdict — the narrative, printed exactly as Pass N returned it, section headings and all. It goes first because in `pr` mode it is what the user asked for, and because a reader who does not yet know what the change *does* cannot evaluate a list of findings about it. It is the only thing that ever precedes the verdict line.

```
WHAT THIS CHANGE DOES — <branch, or PR #<n>: <title>>
vocabulary: <ddd-principles | atom-defaults> · <url, in pr-remote mode>

<HEADLINE, as prose>

WHAT CHANGED
  • ...

NEW OR CHANGED RULES
  • ...

LIFECYCLE AND FLOW
  • ...

BOUNDARIES AND CONTRACTS
  • ...

NOT IN THIS CHANGE
  • ...
```

Rules for the narrative block:

- **Print it verbatim.** Do not rewrite it in your own words, do not "improve" it, and above all do not merge it with what you know about the change. You have the producer context; Pass N does not, and that is the point. Editing it with your own knowledge silently converts an independent reading back into the author's claim.
- **Collapse empty sections to one line** (`NEW OR CHANGED RULES — none`) rather than dropping them. `none` is information: it says the change has no rule impact, which is different from nobody having looked.
- **When the narrative and the PR title disagree, say so, right here, in one line.** `⚠ the PR title says <x>; the code says <y>.` This is the highest-value line this mode can emit and it is easy to leave out politely. Do not editorialize on it — state both and let the reader decide.
- On `VOCAB: atom-defaults`, add one line: `no .lattice/standards/ddd-principles.md in this repo — the narrative uses generic DDD terms; /lattice:ddd-refiner would give it the project's own.` One line, once, no pitch.
- On a Pass N isolation leak (Step 6), prefix the block `[intent-contaminated]` or omit it entirely.

Then the review block, unchanged in shape:

```
FRESH REVIEW — <COMMIT | COMMIT-WITH-FIXES | DO-NOT-COMMIT>
                 (pr-remote: APPROVE | APPROVE-WITH-COMMENTS | REQUEST-CHANGES)
<branch, or PR #<n> @ <short sha>> · <N> files, +<a>/−<b> · risk: <normal|HIGH> · <elapsed>
passes: lattice <✓n|✗>  cso <✓n|✗>  codex <✓n|⧗ running|✗ reason>  narrative <✓|✗>
not covered here — /ship Step 9 owns: performance, data-migration, api-contract, red-team.
                   (Codex-off run: cross-model is also not covered — re-run with codex for it.)

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

Rules:

- The verdict is the first line of the review block, and the narrative block is the only thing permitted above it. Never bury it under a preamble.
- In pr-remote mode the header names the **PR and the commit reviewed**, not your branch — and it names `PR_HEAD`, which on `HEAD_DRIFT: yes` is not what `gh` reported. Add `⚠ PR was updated during this review` on drift, and `⚠ PR state: MERGED` (or `CLOSED`) when it is not open, so nobody acts on `REQUEST-CHANGES` for something that already landed.
- `narrative ✗` in the pass line means Pass N failed or was not run. In `review` mode omit the field entirely rather than printing `narrative —`.
- **`codex` in the pass line has three shapes.** When `CODEX_REQUESTED: 0`, **omit the `codex` field entirely** — a Codex-off run makes no claim about Codex, exactly as `review` mode omits `narrative`. When it was requested but `HAS_CODEX: 0`, print `codex ✗ not installed`. When it ran, print `codex ✓n` / `⧗ running` / `✗ <reason>` as before. Never print `codex ✓0` on a run that did not launch it.
- The `not covered here` line names what this skill structurally does not look at, so a `COMMIT` verdict is never mistaken for full coverage. It is not optional. Keep the parenthetical second line **only on a Codex-off run** (`CODEX_REQUESTED: 0`); drop it when Codex ran. If `HAS_GSTACK: 0`, replace the first line's trailing period with ` — but no gstack install was found, so nothing will run these.`
- **Every finding from every pass appears here**, in one of the four buckets. Deduplicated, with its sources tagged, but never dropped and never deferred to the report file. A bucket with zero findings collapses to a single `BY DESIGN (0)` line.
- Blockers get the full two-line treatment. The other three buckets get one line each.
- `[<sources>]` is the merged source list (`lattice`, `cso`, `codex`) — this is how the user sees which passes converged, which is the signal the cross-model rule is built on.
- The `log:` line is a footer, not a substitute for anything above it.

If more than ~40 findings survive dedup, keep all blockers in full and collapse buckets 3 and 4 to counts plus their highest-severity three, noting the collapse. Do not collapse bucket 2 — an uncited "by design" is the thing most worth seeing.

### Step 8.5: Codex addendum (only when Codex landed late)

**Only reachable when Codex was launched** (`CODEX_REQUESTED: 1`). A Codex-off run has no background task and never enters this step.

When the background task reports completion after Step 8 has printed, compact it (Step 6) and post a short addendum — not a re-print of the whole review:

```
CODEX ADDENDUM (finished <duration>, after the verdict)
verdict impact: <unchanged | now COMMIT-WITH-FIXES | now DO-NOT-COMMIT>
new blockers: <n>   corroborates existing: <n>   noise: <n>
<blocker lines, if any>
```

Then update `$RUN_DIR/report.md` and set `codex.changed_verdict` in the run log. That field is what eventually answers "is Codex worth keeping" with evidence instead of a guess.

### Step 8.6: Hand the run to `/ship`

**Skip this step entirely in pr-remote mode.** The handoff arms a gate on *your* next `/ship` of *your* branch; logging someone else's PR into it would suppress findings on a branch you never reviewed. Say `SHIP_GATE: n/a — reviewed PR #<n>, not this branch` and move on.

**Run before Step 9** — it needs the checkpoint SHA, which the reset destroys.

Build the pass list from the passes that actually ran and returned `STATUS: ok`. Start from `lattice,cso` (dropping either that failed), and append `,codex` **only** when Codex was requested (`CODEX_REQUESTED: 1`) *and* returned `STATUS: ok`. Then:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-handoff.sh" \
  "$RUN_DIR" "$STATUS" "$VERDICT" "$FR_PASSES" "$RUN_DIR/findings.json"
```

- `STATUS` is `clean` only when bucket 1 is empty; otherwise `issues_found`.
- The fourth argument is the comma list of **critic** passes that returned `STATUS: ok` — drop any that failed or were unavailable, **and never include `codex` on a Codex-off run** (it never launched, so it covered nothing), and never include `narrative`. This is load-bearing, not bookkeeping: the ship-side gate only cuts ship's `testing`/`maintainability` specialists if `lattice` is in that list, and only cuts ship's Codex passes if `codex` is. Listing `codex` when it did not run would make ship **skip** its own Codex passes on the strength of a fresh-review pass that never happened — silently removing cross-model coverage from the final gate. The default (Codex-off) run must therefore hand ship `lattice,cso` and let ship run its own Codex. And `narrative` reports no findings at all, so listing it would claim coverage that nothing produced.
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
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-restore.sh" "$RUN_DIR"
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

Write `$RUN_DIR/report.md` (the Step 8 chat output verbatim, plus scope, pass inventory, and isolation-audit result), then `$RUN_DIR/run.json`:

```json
{"skill":"fresh-review","schema":5,"run_id":"<RUN_ID>",
 "ts_start":"<TS_START>","ts_end":"<now>","duration_s":0,
 "repo":"<repo>","branch":"<BRANCH>","base":"<BASE>",
 "mode":"<review|pr>","codex_requested":false,
 "pr":{"number":0,"url":"","state":"","head":"","drift":false},
 "scope":"<REVIEW_SCOPE>","diff_base":"<DIFF_BASE>","checkpoint":"<CHECKPOINT_SHA>","risk":"<RISK>",
 "diff":{"files":0,"lines":0},
 "passes":[
   {"name":"lattice","status":"ok","duration_s":0,"findings":0,"isolation":"clean"},
   {"name":"cso","status":"ok","duration_s":0,"findings":0,"isolation":"clean"},
   {"name":"codex","status":"ok","duration_s":0,"findings":0,"changed_verdict":false},
   {"name":"narrative","status":"ok","duration_s":0,"findings":0,"isolation":"clean",
    "vocab":"<ddd-principles|atom-defaults>","title_mismatch":false}],
 "triage":{"real_bug":0,"by_design":0,"noise":0,"misread":0,"deduped":0},
 "verdict":"<VERDICT>","handoff_rc":0,
 "tools":{"gstack":0,"codex":0,"gh":0}}
```

- Set `codex_requested` to whether `--codex` was passed (`CODEX_REQUESTED` from `state.env`). It is what tells cross-run analysis apart: a `codex` pass absent because it was never asked for versus one dropped because it failed.
- **Omit the `codex` pass from `passes[]` when `codex_requested` is `false`** — a pass that never launched is not a pass that failed, and `codex_requested` already records the choice. When it was requested but failed or was unavailable, keep the entry with `"status":"failed"` so the failure stays visible.
- Omit `pr` outside pr-remote mode and the `narrative` pass outside `pr` mode — an absent pass and a failed one must stay distinguishable.
- `tools.codex` stays availability (`HAS_CODEX`), independent of whether the run requested Codex.

Then:

```bash
FR_STATUS="$STATUS" bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-log.sh" "$RUN_DIR"
```

The script validates the JSON, appends it as one line to `$LOG_DIR/runs.jsonl`, prunes old run directories to `FR_RUN_RETENTION`, and pings the gstack timeline. Validation **gates** the append rather than following it: a malformed line in `runs.jsonl` breaks every future analysis of it. On `RUN_JSON: invalid`, `$RUN_DIR/run.json` is kept — tell the user the index entry was skipped, and why.

Fill the zeroed fields from the actual run — per-pass wall time, per-pass finding counts, and the triage bucket counts. Those are the point of the log, not decoration.

**What this log is for.** Three questions it is designed to answer across runs:

- *Where does the time actually go?* Per-pass `duration_s` replaces the impression that "the run is slow" with the name of the pass that is slow.
- *Is Codex earning its place?* Now that Codex is opt-in, the question is two-sided: `codex_requested` across runs shows how often anyone reaches for it, and `codex.duration_s` against `codex.changed_verdict` over the runs that did request it is the evidence for whether it pays off when they do.
- *Which pass produces noise?* A pass whose findings land overwhelmingly in buckets 3 and 4 is miscalibrated for this repo and should be re-scoped or dropped.
- *Is the narrative telling anyone anything?* `narrative.title_mismatch` over many pr-remote runs is the direct measure. If it is never true, the mode is producing pleasant restatements and its isolation is not buying what it costs; if it is often true, PR descriptions in this repo are not to be trusted, which is worth knowing on its own.

**Schema history.** `schema:5` adds `codex_requested` and makes the `codex` pass optional — absent when the run did not request Codex. Reading a `schema:4` entry, treat `codex_requested` as absent-unknown but assume `true`, since Codex ran unconditionally then and its pass will be present. `schema:4` adds `mode`, an optional `pr` object, and an optional fourth `narrative` pass. `schema:3` has three passes and no mode field — read its absence as `review`, since pr mode did not exist. `schema:2` entries carry a different fourth pass, `gstack`, from when this skill ran `/review` itself; a tool reading across versions must not treat either fourth pass's absence as a failure, and must not confuse the two — `gstack` reported findings, `narrative` never does. The shape is otherwise deliberately generic — `skill`, `run_id`, `duration_s`, `passes[]`, `verdict` — so a future cross-skill run-analysis tool can read it alongside other skills' logs without a per-skill parser.

## Failure modes and recovery

- **Checkpoint commit fails** (`CHECKPOINT: failed`) → no-checkpoint mode (Step 3), document it, and **still run `fr-restore.sh`** — `git add -A` already ran, so the index needs restoring even though there is no commit to reset.
- **Unmerged index** (`STOP_REASON: unmerged_index`) → stop at preflight. Resolve the conflict, then re-run.
- **A pass returns nothing / errors** → log it as skipped, drop it from the `passes` list in Step 8.6, and continue. No single pass is blocking, but the verdict must name the absent lens.
- **A pass ignores the compact return contract** and dumps prose → do not re-read it; note it in NOTES, extract findings from its `raw/` file with a compactor subagent as in Step 6.
- **Codex times out / fails** (only possible when `--codex` was requested) → verdict ships Claude-only, `CODEX_FAILED` in the log, the `codex` pass kept with `"status":"failed"`. Never substitute a Claude pass for it. Fix is `codex login` and re-run.
- **Codex not requested** (`CODEX_REQUESTED: 0`, the default) → not a failure. Pass C never launches, the pass line omits `codex`, and the run log records `codex_requested:false` with no `codex` pass. Mention once that `--codex` adds a cross-model pass if the user wants it; do not treat its absence as reduced coverage.
- **Subagent tries to fix code** → Step 6.5 catches it; `--revert` undoes it unless the checkpoint failed.
- **User aborts midway** → `fr-restore.sh "$RUN_DIR"` first, then report what was collected.
- **Forbidden read detected** → Step 6 handles it: note, downgrade confidence, optionally re-spawn. A Pass N leak is the exception — label the narrative contaminated or drop it, never print it clean.
- **`runs.jsonl` fails to validate** → the line is dropped, `$RUN_DIR/run.json` is kept, tell the user.
- **Handoff fails** (`SHIP_GATE: will_not_fire`) → continue, and tell the user ship will re-dispatch its full army and re-ask about triaged findings.
- **`PR: unresolved`** → stop, print `REASON` and its remedy from Step 1.5. Never fall back to reviewing the local branch: it would answer a question about PR #42 with a review of something else entirely.
- **Pass N returns prose instead of the block**, or returns file paths and function names → do not print it. Re-spawn once with the constraint list repeated; on a second failure print the review block alone and note `narrative ✗ format`. A narrative full of file paths is a diff summary, which the user can already get from `git diff --stat`.
- **Pass N invents a domain story for a tooling-only change** → print the review block alone and note it. This is the failure that makes the whole mode untrustworthy, so it is worth a `NOTES` line in the run log rather than a silent drop.
- **PR head moves mid-review** (`HEAD_DRIFT: yes`) → not an error. Everything was reviewed at `PR_HEAD`; say so in the header and move on. Do not re-fetch — that would mix two commits' findings in one report.
- **PR worktree survives the run** (`WORKTREE: failed`) → tell the user the path and that `git worktree remove --force <path>` clears it. Do not leave it undisclosed; it is a full checkout's worth of disk.

## What this skill does NOT do

- **Run gstack's `/review`.** Deliberate — see "Why gstack's `/review` is not a pass here". `performance`, `data-migration`, `api-contract`, and Red Team are `/ship`'s to run, on the final diff.
- **Open a literal fresh Claude Code session.** For maximum isolation before a major release: `git worktree add ../review-wt HEAD`, start Claude Code there, run the commands manually.
- **Auto-apply fixes.** The calling session applies fixes after triage. This skill only diagnoses.
- **Replace a full security audit.** `/cso --diff` covers the changed surface only. A full `/cso` remains a periodic job.
- **Replace QA.** Nothing here proves the code runs. `/qa` still applies.
- **Run the CI gates.** Tests, coverage, and lint are `/ship`'s job. A `COMMIT` verdict says the code reads correctly, not that it passes.
- **Stop `/ship` from reviewing again.** Ship's pre-landing review is unconditional and reviews the *final* diff — post-fix, post-CHANGELOG, post-base-merge — a different artifact from what these passes saw. `references/ship-dispatch-gate.md` trims the parts that are genuinely duplicated; the rest is supposed to run.
- **Analyze runs across sessions.** The log is written to be analyzable; reading it is a separate tool's job.
- **Post anything to GitHub.** The narrative is printed to chat and written to disk, never sent. No `gh pr comment`, no `gh pr review`, no `gh pr edit --body`, not even in pr-remote mode where a PR is plainly sitting there — publishing a review under the user's name is theirs to decide, and an unattended run inside `/loop` must not be able to do it. If they want it posted, they will say so, and that is a separate action taken with the text in front of them.
- **Modify the PR under review.** pr-remote mode is read-only on someone else's branch. Findings are comments; the worktree is disposable and gets deleted.
- **Review a PR from another repo.** `foreign_repo` stops it. There is no local tree to materialize the head into, and a patch without its source tree produces reviewers reading the wrong file contents. Clone that repo and run there.
- **Replace reading the diff.** The narrative is at product altitude by construction — no paths, no names, no code. It tells you what changed and what it means; it cannot tell you whether line 84 is right. It is an orientation and a cross-check, not a substitute for review, which is exactly why this mode never ships it without one.

## Examples

**"fresh review my changes before I commit"** → the default run: Steps 1–10, `--codex` **not** passed; branch-scoped packet built once; two isolated Claude subagents (lattice + `/cso`), no Codex; verdict and every finding printed to chat; tree restored; run logged. No questions asked at any point.

**"fresh review with codex"** / **"review my changes, cross-model too"** → `--codex`. Same run plus Pass C launched in the background alongside the two subagents; the pass line shows `codex`, and Step 8.5 posts an addendum if it lands late. Everything else is identical to the default.

**"review this before I push"** with `auth/` in the diff → `fr-packet.sh` returns `RISK: high` on `PATH_HITS`; `/cso` upgrades to `--diff --comprehensive`. Risk does **not** pull in Codex — this is still a two-source run unless the user also asked for `--codex`; the sources are triaged under the security floor.

**"fresh review, then ship"** → the default (Codex-off) run, nothing added. The handoff hands ship `lattice,cso`, so ship trims its `testing`/`maintainability` specialists but **runs its own Codex** on the final diff. Had the run used `--codex`, the handoff would add `codex` and ship would trim its Codex passes too.

**Codex still running when the Claude passes return** (a `--codex` run) → verdict prints as `codex ⧗ running`; the background task completes eight minutes later; Step 8.5 posts the addendum and records whether it moved the verdict.

**"pr review — what does this actually change?"** on your own branch → `--mode pr`. Same checkpoint, same packet, the two Claude critics, plus Pass N and Step 4.5's vocabulary resolution — no Codex, since it was not requested. Chat gets the narrative, then the verdict and every finding. Handoff and restore run as normal, because this is still your branch.

**"review PR 42"** → `--pr 42`. Step 1.5 resolves it, fetches `pull/42/head`, and builds a detached worktree; Step 3 is skipped; the two critics and Pass N read the PR's diff and open files from the PR's tree (add `--codex` for a cross-model pass too). Verdict prints as `APPROVE-WITH-COMMENTS`, bucket 2 admits only standards citations, no handoff, and Step 9 deletes the worktree. Your own uncommitted work is untouched throughout — and nothing is posted to the PR.

**"explain PR 42 for the standup"** with no `.lattice/standards/ddd-principles.md` → identical run, `VOCAB: atom-defaults`. The narrative uses generic domain terms and nouns lifted from the code's own naming, the report says so in one line, and the review still runs in full.

**A tooling-only PR** — CI workflow and lockfile → Pass N returns `HEADLINE: this change has no domain meaning; it is CI and dependency work`, every domain section `none`. That is the correct output, printed as-is. `RISK: high` still fires on the IaC path, so `/cso` runs comprehensive over it.

**The PR title says "add refund support"; the narrative says a fee is recorded but never reversed** → the `⚠` mismatch line in Step 8, `title_mismatch: true` in the run log. This is the outcome the whole isolation contract exists to make possible.
