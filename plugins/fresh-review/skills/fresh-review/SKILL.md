---
name: fresh-review
description: |
  Pre-commit fresh-eyes code review. Orchestrates a context-isolated review pass that approximates what
  a new reviewer would catch — runs the lattice review, the gstack security audit, and a cross-model
  Codex pass against one shared diff packet, via subagents that cannot read design docs, intent, or
  prior session context. Triages findings against the producer-context, prints the verdict and every
  finding to chat, and logs the run for later analysis.

  Deliberately does NOT run gstack's `/review`. That skill is what `/ship` runs unconditionally at its
  own Step 9, on the final diff; running it here too pays for the same specialist army twice. This
  skill covers craft, security, and cross-model ground; `/ship` covers the structural specialists.

  Use when the user asks to "fresh review", "fresh-eyes review", "review my changes", "pre-commit
  review", "review before commit", "review with no bias", "independent review", "what did I miss",
  "check my work before I commit", "context-free review", or "review with fresh eyes". Proactively
  suggest before any /ship, /land-and-deploy, or manual git commit when the diff exceeds ~50 lines or
  touches auth, payments, migrations, or security-sensitive code.

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

Pre-commit code review with enforced producer/reviewer context separation.

## Why this skill exists

When you design, write, and review code in the same session, the reviewer-Claude already agrees with the design choices and knows the rationale. It rationalizes away its own decisions. Real review needs the reviewer to *lack* context the producer has. This skill enforces that separation by spawning subagents with strict context restrictions, adding a genuinely out-of-process cross-model reviewer, and then triaging their findings back in the producer context (where intent is known and "by design" can be properly justified).

## Configuration

```
LATTICE_REVIEW_CMD="/lattice:review"     # Lattice standards conformance (plugin-namespaced)
CSO_CMD="/cso --diff"                    # gstack security audit, scoped to branch changes
CODEX_JOIN_BUDGET=240                    # seconds to wait for Codex after the Claude passes return
FR_RUN_RETENTION=20                      # run directories kept before pruning (env var, read by fr-log.sh)
```

- Review scope is resolved mechanically by `fr-preflight.sh`: `branch` (merge-base..worktree) whenever an `origin/<base>` exists to merge-base against, `working` otherwise. `branch` matches what a human PR reviewer sees, and a Lattice `checkpoint_mode: continuous` session already has WIP commits on the branch that `working` scope would silently skip.
- `/cso --diff` scopes the audit to changed files and keeps daily mode's 8/10 confidence gate. High-risk diffs upgrade to `--diff --comprehensive` (Step 4).
- **Codex runs here as a full pass**, in the background, concurrent with the others. Rationale in Pass C.

## Why gstack's `/review` is not a pass here

`/review` is the exact skill `/ship` runs at its own Step 9 — unconditionally, with no "already reviewed?" gate on dispatch. Its only filters are a `DIFF_LINES < 50` floor, scope detection, and an adaptive gate that needs 10+ dispatches at zero findings before it ever fires. `skip_eng_review` does not help: it flips one row on ship's readiness dashboard and ship then says outright to continue without blocking, because it runs its own review in Step 9 regardless.

So a fresh-review that ran `/review` and was then followed by `/ship` paid for the same seven specialists, Red Team, and adversarial subagent twice — and worse, ship's Step 9 stops for fixes and asks for a re-run, so the full army re-dispatches on every fix cycle.

The division of labor is therefore fixed, not configurable:

| | fresh-review (this skill) | `/ship` Step 9 / Step 11 |
|---|---|---|
| Craft and standards conformance | Pass A (lattice) | — |
| Security | Pass B (`/cso`, confidence-gated) | `security` specialist (ungated) |
| Cross-model review | Pass C (`codex review`) | Codex structured + adversarial |
| performance, data-migration, api-contract, Red Team | **not covered** | owned here |
| Reviews which artifact | the pre-commit checkpoint | the final diff, post-fix, post-base-merge |

The four structural specialists and Red Team are genuinely absent from this skill. That is the trade: they run once, at ship time, against the diff that actually lands. If you want them *before* commit, the answer is `/review` directly, not this skill.

The reverse redundancy — ship re-running what *this* skill already did — is handled from the ship side by `references/ship-dispatch-gate.md`.

## Output contract

Two audiences, two artifacts. Do not confuse them.

- **Chat is for the human.** It gets the verdict on the first line and *every* finding from *every* pass, merged and triaged. It is never a pointer to a file. "Full report at `<path>`" is not an acceptable substitute for the findings themselves.
- **Disk is for the agents and for later analysis.** Raw pass reports, the diff packet, and the run log live in the run directory. Nothing there is required reading for the user.

## Token discipline

Four invariants. Every step below is built around them; violating one silently makes the run cost several times what it should.

1. **The orchestrator never loads the diff.** `fr-packet.sh` classifies risk with `grep -c` over the patch and prints only counts. The full patch enters no context but the subagents' own.
2. **Reviewers read the packet, not git.** The diff is materialized once (Step 4) and every pass is handed the same file paths. No pass re-derives scope, and no pass runs `git diff` — which also guarantees their findings are comparable.
3. **Passes return compact findings; prose goes to disk.** This is the largest saving by far. `/cso` alone emits thirteen numbered phases of narrative; the compact block is a few hundred tokens. Each pass writes its full report to `$RUN_DIR/raw/` and returns only the fixed-format block in Step 5.
4. **Raw reports are not read back.** Triage runs on the compact blocks. Open a raw report only to disambiguate one specific finding, and read only that finding's section.

The same principle governs the shell work: every mechanical step is a script in `${CLAUDE_PLUGIN_ROOT}/scripts/` that prints a small delimited key block. Read the block, not the machinery. Do not reimplement a script's logic inline — the scripts are where the gating rules are actually enforced, and a hand-typed variant of one is how those rules get lost.

## Workflow

Steps run in order. Step 5 is one parallel fan-out; everything else is sequential.

Every script takes `$RUN_DIR` and reads the rest of its inputs from `$RUN_DIR/state.env`, which `fr-preflight.sh` creates and later scripts append to. You never have to thread variables between Bash calls by hand — and because state lives on disk, a run interrupted mid-way can still be restored on the next turn.

### Step 1: Preflight

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-preflight.sh"
```

This probes the repo, resolves the review scope, creates the run directory, and writes `state.env`. Export `RUN_DIR` from its output — every later script takes it as `$1`.

On `STATUS: stop`, tell the user and stop. `STOP_REASON` is one of:

- `not_a_repo` — nothing to do here.
- `nothing_to_review` — no dirt and no commits the base branch lacks.
- `unmerged_index` — a conflict is in progress. Do **not** checkpoint a conflicted tree; a half-merged tree is not a reviewable diff. Resolve it, then re-run.

`AHEAD` counts commits **not in the base branch** (`$DIFF_BASE..HEAD`) — deliberately not `@{upstream}..HEAD`. Comparing a branch against its own upstream asks the wrong question: a fully pushed PR branch reports `AHEAD=0` even though its PR diff is a hundred commits wide, and a branch with no upstream falls back to `0`. Either would stop the skill with "nothing to review" while a complete, reviewable diff sits in front of it. The `@{upstream}` form survives only as the degraded fallback for when there is no `origin/$BASE` to merge-base against.

Tool-availability accounting — state each of these up front, never silently:

- `HAS_GSTACK: 0` → `/cso` does not exist here. **One of three passes cannot run.** Say so plainly, run Pass A and Pass C, label the verdict reduced-lens. Discovering this inside a subagent instead wastes the run and produces a report that looks complete but isn't. Note also that no gstack install means no `/ship` either, so the structural specialists this skill defers to will never run at all.
- `HAS_CODEX: 0` → no cross-model coverage. Say so; do not substitute a Claude pass for it.
- `CODEX_CFG: unknown` → `gstack-config` was not found, so the setting could not be read. Report unknown, never guess `enabled`. This setting gates *gstack's* internal Codex, not ours; Pass C runs on `HAS_CODEX` alone.

Two other outputs matter later:

- `DIRTY: 0` with `AHEAD > 0` → the branch carries commits the base does not, pushed or not. Review them: the checkpoint self-skips in Step 3, scope stays `branch`. This is the normal shape of an open PR whose work is fully committed and pushed.
- `INDEX_TREE` is a real tree object written from the pre-review index, so it carries the staged *content* of every path, not just its name. Step 9 restores from it **exactly**. A name list cannot do this: a partially staged file — some hunks in the index, others not — restores by re-staging the whole file, silently folding the unstaged hunks in and destroying the split the user built.

The run directory persists, unlike a `mktemp` scratch dir — it is the record that makes a run analyzable afterward. It lives under `.fresh-review/` when that path is already gitignored, and under the git dir otherwise. The script never appends to `.gitignore`: mutating a tracked file mid-review would inject a change into the diff under review.

`LOG_DIR` is deliberately the **common** git dir, not the per-worktree one. In a worktree `git rev-parse --git-dir` resolves to `.git/worktrees/<name>`, so an index written there would fragment across worktrees and be deleted with them — and cross-run analysis would silently see only a fraction of the history. Run directories stay local and disposable; the index in `LOG_DIR` is the durable record. Entries may therefore outlive the run directory they point at, which is expected.

### Step 2: State the scope

`fr-preflight.sh` already printed `REVIEW_SCOPE` and `DIFF_CMD`. Say them out loud — one canonical scope string, handed identically to every reviewer so their findings are comparable. Nothing is materialized yet; the packet is built in Step 4, after the checkpoint, so that untracked files are in it.

### Step 3: WIP checkpoint

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

Codex depth is deliberately *not* gated on risk — Pass C runs the structured review every time, and since it is off the critical path there is nothing to save by skipping it.

State the file count and risk class out loud. If `LINES` exceeds ~2000, warn that reviewer quality degrades at that size and that a re-run scoped to a subdirectory reads more carefully — then **proceed anyway**. This skill never blocks on a question: it is meant to run unattended, including inside `/loop`. Every branch point resolves to a default and says which default it took.

### Step 5: Fan out all reviewers (one parallel batch)

Launch the two Claude subagents **and** the Codex background command **in a single message**. Codex overlapping the others is the entire reason it stopped being a latency problem.

Every subagent prompt opens with this **isolation contract**, verbatim:

> Fresh-eyes pre-commit review. You have no prior context. That is intentional and required.
>
> **Your input is a prepared packet. Do not run `git diff`, `git log`, or `gh` — the scope is already resolved for you:**
> - `{{RUN_DIR}}/packet/diff.patch` — the complete diff under review
> - `{{RUN_DIR}}/packet/files.txt` — changed files with status
> - `{{RUN_DIR}}/packet/stat.txt` — per-file line counts
> - `{{RUN_DIR}}/packet/scope.txt` — the resolved scope
>
> Read `diff.patch` first. Open a source file from the worktree only when the diff alone cannot tell you whether something is a defect — not to browse.
>
> **Forbidden reads** — do not open these even if they look relevant, *and do not open them because a skill you invoke tells you to*: `.lattice/requirements/**`, `.lattice/contexts/**`, `.lattice/reviews/**`, `*.plan.md`, `*.design.md`, `docs/decisions/**`, `TODOS.md`, `ONBOARDING.md`, anything under `~/.gstack/projects/**`, and any file whose purpose is to record intent rather than behavior. **Forbidden commands**: `gh pr view`, `gh issue view`, `gh pr diff --body`, `git log`. Allowed: `.lattice/standards/**`, `.lattice/learnings/**`, `.lattice/config.yaml`, `AGENTS.md`/`CLAUDE.md`, and the diffed source. (Learnings are repo-wide rules, not this change's intent — read them, never write them.)
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

**Pass C — Codex** (background Bash, launched in the same message, not a subagent)

```bash
( codex review --base "$BASE" \
    -c sandbox_mode="read-only" -c approval_policy="never" \
    -c 'model_reasoning_effort="high"' \
    < /dev/null > "$RUN_DIR/raw/codex.md" 2> "$RUN_DIR/raw/codex.err"
  echo $? > "$RUN_DIR/raw/codex.rc" )
```

Use `run_in_background: true`. Never set a Bash `timeout` on this — a timeout is a hard kill that burns the full budget and discards the work. Backgrounding makes the budget a *join deadline* instead, and the harness re-invokes you when the command exits.

Four things about this invocation are deliberate:

- **`codex review`, not `codex exec`.** `review` scopes natively and emits structured, severity-marked findings that drop into the triage table. `exec` returns prose that would have to be parsed. gstack uses `exec` for its adversarial pass and gates `review` at 200+ lines as its own cost control; that gating does not bind us once Codex is off the critical path.
- **`--base`, and therefore no custom prompt.** The CLI rejects `[PROMPT]` together with `--base` (`error: the argument '[PROMPT]' cannot be used with '--base <BRANCH>'`), so the isolation contract cannot be injected. `--base` still wins: a separate process running a different model family with no conversation history is the strongest isolation of any pass here, and handing it the base branch avoids spending agentic turns rediscovering the diff. For `REVIEW_SCOPE="working"`, use `--commit "$CHECKPOINT_SHA"` instead.
- **`approval_policy="never"` and `sandbox_mode="read-only"`.** A non-interactive background run that stalls on an approval prompt is indistinguishable from a slow one. Read-only also enforces "do not fix anything" at the process level rather than by instruction.
- **No `--enable web_search_cached`.** gstack enables it; for a diff review it rarely pays and it adds latency.

Budget expectations: measured floor is ~30s on an *empty* diff (process start, git probe, one model round trip). Real diffs run minutes. That floor is why Codex must never gate the verdict.

### Step 6: Join and isolation audit

When the Claude passes have returned, check Codex once:

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

Neither remaining Claude pass natively hunts for intent — that was `/review`'s habit, and `/review` no longer runs here. So a forbidden read from Pass A, Pass B, or the compactor is genuinely anomalous rather than expected, and deserves more weight than a routine leak: investigate it instead of noting it and moving on.

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

**Untracked files are only listed, never cleaned.** `git clean` here could delete real work — a build artifact, a watcher's output, or a file the user created a second ago. Report `UNTRACKED_REMAINING` and let them decide.

Record any violation, and treat that pass's findings as still valid but its judgment as suspect: a reviewer that ignored "do not fix" may have ignored the forbidden-reads list too.

### Step 7: Triage

You are back in the producer context with full knowledge of design intent. Work from the compact blocks. Deduplicate across passes (same `file:line` + same root cause = one finding, sources merged), then assign each to exactly one bucket:

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

  With three passes, convergence is *rarer* than it would be with a nested specialist army — but not *weaker*. The rows above keep exactly the weight they state, and a finding raised by one pass alone is still a finding raised by one pass alone. Do not loosen bucket 2's citation requirement, or relax the security floor, to compensate for thinner agreement: the correct response to fewer lenses is a more conservative verdict, not a lower bar.

Write the merged pre-triage findings to `$RUN_DIR/findings.tsv` for the log.

### Step 8: Report to chat

**This is the primary output.** Print it in full, in chat, in this shape. Verdict first, always.

```
FRESH REVIEW — <COMMIT | COMMIT-WITH-FIXES | DO-NOT-COMMIT>
<branch> · <N> files, +<a>/−<b> · risk: <normal|HIGH> · <elapsed>
passes: lattice <✓n|✗>  cso <✓n|✗>  codex <✓n|⧗ running|✗ reason>
not covered here — /ship Step 9 owns: performance, data-migration, api-contract, red-team.

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

- The verdict is the first line. Never bury it under a preamble.
- The `not covered here` line names what this skill structurally does not look at, so a `COMMIT` verdict is never mistaken for full coverage. It is not optional. If `HAS_GSTACK: 0`, replace the trailing period with ` — but no gstack install was found, so nothing will run these.`
- **Every finding from every pass appears here**, in one of the four buckets. Deduplicated, with its sources tagged, but never dropped and never deferred to the report file. A bucket with zero findings collapses to a single `BY DESIGN (0)` line.
- Blockers get the full two-line treatment. The other three buckets get one line each.
- `[<sources>]` is the merged source list (`lattice`, `cso`, `codex`) — this is how the user sees which passes converged, which is the signal the cross-model rule is built on.
- The `log:` line is a footer, not a substitute for anything above it.

If more than ~40 findings survive dedup, keep all blockers in full and collapse buckets 3 and 4 to counts plus their highest-severity three, noting the collapse. Do not collapse bucket 2 — an uncited "by design" is the thing most worth seeing.

### Step 8.5: Codex addendum (only when Codex landed late)

When the background task reports completion after Step 8 has printed, compact it (Step 6) and post a short addendum — not a re-print of the whole review:

```
CODEX ADDENDUM (finished <duration>, after the verdict)
verdict impact: <unchanged | now COMMIT-WITH-FIXES | now DO-NOT-COMMIT>
new blockers: <n>   corroborates existing: <n>   noise: <n>
<blocker lines, if any>
```

Then update `$RUN_DIR/report.md` and set `codex.changed_verdict` in the run log. That field is what eventually answers "is Codex worth keeping" with evidence instead of a guess.

### Step 8.6: Hand the run to `/ship`

**Run before Step 9** — it needs the checkpoint SHA, which the reset destroys.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-handoff.sh" \
  "$RUN_DIR" "$STATUS" "$VERDICT" "lattice,cso,codex" "$RUN_DIR/findings.json"
```

- `STATUS` is `clean` only when bucket 1 is empty; otherwise `issues_found`.
- The fourth argument is the comma list of passes that returned `STATUS: ok` — drop any that failed or were unavailable. This is load-bearing, not bookkeeping: the ship-side gate only cuts ship's `testing`/`maintainability` specialists if `lattice` is in that list, and only cuts ship's Codex passes if `codex` is. A pass you list but did not actually run silently removes a lens from the final gate.
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

Two independent undos, each separately gated, which is why this is a script:

- `RESET` drops the checkpoint commit — **only** when it actually landed. Resetting after a failed commit would throw away the user's last real commit. The script also verifies HEAD still *is* the checkpoint before resetting, so a re-run after an interrupted pass reports `skipped_already_reset` instead of eating a commit.
- `INDEX` restores the pre-review index with `git read-tree`, whenever `git add -A` ran — **including on `CHECKPOINT=failed`**. That is the case a "skip the restore in no-checkpoint mode" rule gets wrong: `add` had already staged everything. `read-tree` does not touch the worktree, so the staged/unstaged split comes back exactly as it was, including partially staged files that a re-`git add` by filename would have flattened.

Both are skipped when `CHECKPOINT=skipped` — nothing was staged, nothing was committed, nothing to undo.

Then tell the user: "Working tree restored — staged/unstaged split is back as it was."

This must run even on abort or error. If the user interrupts mid-review, restoring the tree is the first thing you do on the next turn — `state.env` survives, so `fr-restore.sh "$RUN_DIR"` is all it takes.

### Step 10: Persist the run log

Write `$RUN_DIR/report.md` (the Step 8 chat output verbatim, plus scope, pass inventory, and isolation-audit result), then `$RUN_DIR/run.json`:

```json
{"skill":"fresh-review","schema":3,"run_id":"<RUN_ID>",
 "ts_start":"<TS_START>","ts_end":"<now>","duration_s":0,
 "repo":"<repo>","branch":"<BRANCH>","base":"<BASE>",
 "scope":"<REVIEW_SCOPE>","diff_base":"<DIFF_BASE>","checkpoint":"<CHECKPOINT_SHA>","risk":"<RISK>",
 "diff":{"files":0,"lines":0},
 "passes":[
   {"name":"lattice","status":"ok","duration_s":0,"findings":0,"isolation":"clean"},
   {"name":"cso","status":"ok","duration_s":0,"findings":0,"isolation":"clean"},
   {"name":"codex","status":"ok","duration_s":0,"findings":0,"changed_verdict":false}],
 "triage":{"real_bug":0,"by_design":0,"noise":0,"misread":0,"deduped":0},
 "verdict":"<VERDICT>","handoff_rc":0,
 "tools":{"gstack":0,"codex":0}}
```

Then:

```bash
FR_STATUS="$STATUS" bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-log.sh" "$RUN_DIR"
```

The script validates the JSON, appends it as one line to `$LOG_DIR/runs.jsonl`, prunes old run directories to `FR_RUN_RETENTION`, and pings the gstack timeline. Validation **gates** the append rather than following it: a malformed line in `runs.jsonl` breaks every future analysis of it. On `RUN_JSON: invalid`, `$RUN_DIR/run.json` is kept — tell the user the index entry was skipped, and why.

Fill the zeroed fields from the actual run — per-pass wall time, per-pass finding counts, and the triage bucket counts. Those are the point of the log, not decoration.

**What this log is for.** Three questions it is designed to answer across runs:

- *Where does the time actually go?* Per-pass `duration_s` replaces the impression that "the run is slow" with the name of the pass that is slow.
- *Is Codex earning its place?* `codex.duration_s` against `codex.changed_verdict` over a dozen runs is the evidence for keeping or dropping it.
- *Which pass produces noise?* A pass whose findings land overwhelmingly in buckets 3 and 4 is miscalibrated for this repo and should be re-scoped or dropped.

**Schema history.** `schema:3` has three passes. `schema:2` entries carry a fourth `gstack` pass from when this skill ran `/review` itself; an analysis tool reading both must not treat that pass's absence in `schema:3` as a failure. The shape is otherwise deliberately generic — `skill`, `run_id`, `duration_s`, `passes[]`, `verdict` — so a future cross-skill run-analysis tool can read it alongside other skills' logs without a per-skill parser.

## Failure modes and recovery

- **Checkpoint commit fails** (`CHECKPOINT: failed`) → no-checkpoint mode (Step 3), document it, and **still run `fr-restore.sh`** — `git add -A` already ran, so the index needs restoring even though there is no commit to reset.
- **Unmerged index** (`STOP_REASON: unmerged_index`) → stop at preflight. Resolve the conflict, then re-run.
- **A pass returns nothing / errors** → log it as skipped, drop it from the `passes` list in Step 8.6, and continue. No single pass is blocking, but the verdict must name the absent lens.
- **A pass ignores the compact return contract** and dumps prose → do not re-read it; note it in NOTES, extract findings from its `raw/` file with a compactor subagent as in Step 6.
- **Codex times out / fails** → verdict ships Claude-only, `CODEX_FAILED` in the log, `codex` omitted from the `passes` list. Never substitute a Claude pass for it. Fix is `codex login` and re-run.
- **Subagent tries to fix code** → Step 6.5 catches it; `--revert` undoes it unless the checkpoint failed.
- **User aborts midway** → `fr-restore.sh "$RUN_DIR"` first, then report what was collected.
- **Forbidden read detected** → Step 6 handles it: note, downgrade confidence, optionally re-spawn.
- **`runs.jsonl` fails to validate** → the line is dropped, `$RUN_DIR/run.json` is kept, tell the user.
- **Handoff fails** (`SHIP_GATE: will_not_fire`) → continue, and tell the user ship will re-dispatch its full army and re-ask about triaged findings.

## What this skill does NOT do

- **Run gstack's `/review`.** Deliberate — see "Why gstack's `/review` is not a pass here". `performance`, `data-migration`, `api-contract`, and Red Team are `/ship`'s to run, on the final diff.
- **Open a literal fresh Claude Code session.** For maximum isolation before a major release: `git worktree add ../review-wt HEAD`, start Claude Code there, run the commands manually.
- **Auto-apply fixes.** The calling session applies fixes after triage. This skill only diagnoses.
- **Replace a full security audit.** `/cso --diff` covers the changed surface only. A full `/cso` remains a periodic job.
- **Replace QA.** Nothing here proves the code runs. `/qa` still applies.
- **Run the CI gates.** Tests, coverage, and lint are `/ship`'s job. A `COMMIT` verdict says the code reads correctly, not that it passes.
- **Stop `/ship` from reviewing again.** Ship's pre-landing review is unconditional and reviews the *final* diff — post-fix, post-CHANGELOG, post-base-merge — a different artifact from what these passes saw. `references/ship-dispatch-gate.md` trims the parts that are genuinely duplicated; the rest is supposed to run.
- **Analyze runs across sessions.** The log is written to be analyzable; reading it is a separate tool's job.

## Examples

**"fresh review my changes before I commit"** → Steps 1–10; branch-scoped packet built once; two isolated subagents plus Codex in background, all launched together; verdict and every finding printed to chat; tree restored; run logged. No questions asked at any point.

**"review this before I push"** with `auth/` in the diff → `fr-packet.sh` returns `RISK: high` on `PATH_HITS`; `/cso` upgrades to `--diff --comprehensive`; three sources triaged under the security floor.

**"fresh review, then ship"** → identical run; nothing is skipped or added, because this skill has one mode. The handoff arms the ship-side gate, and `/ship` then trims the specialists this run already covered while still running the four structural ones on the final diff.

**Codex still running when the Claude passes return** → verdict prints as `codex ⧗ running`; the background task completes eight minutes later; Step 8.5 posts the addendum and records whether it moved the verdict.
