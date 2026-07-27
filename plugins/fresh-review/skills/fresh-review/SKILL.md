---
name: fresh-review
description: |
  Pre-commit fresh-eyes code review. Orchestrates a context-isolated review pass that approximates what
  a new reviewer would catch — runs the lattice review, a constrained gstack review, the gstack security
  audit, and a cross-model Codex pass against one shared diff packet, via subagents that cannot read
  design docs, intent, or prior session context. Triages findings against the producer-context, prints
  the verdict and every finding to chat, and logs the run for later analysis.

  Use when the user asks to "fresh review", "fresh-eyes review", "review my changes", "pre-commit
  review", "review before commit", "review with no bias", "independent review", "what did I miss",
  "check my work before I commit", "context-free review", or "review with fresh eyes". Proactively
  suggest before any /ship, /land-and-deploy, or manual git commit when the diff exceeds ~50 lines or
  touches auth, payments, migrations, or security-sensitive code.

  This is the right tool whenever the producer-Claude and the reviewer-Claude would otherwise be the
  same instance with the same context — the entire point is to break that bias. Do NOT call
  /lattice:review, /review, or /cso directly when the user wants fresh eyes; those run inside the
  producer context and will rationalize away the producer's own choices.
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
GSTACK_REVIEW_CMD="/review"              # gstack pre-landing review — heavily constrained, see Pass B
CSO_CMD="/cso --diff"                    # gstack security audit, scoped to branch changes
REVIEW_SCOPE="branch"                    # branch = merge-base..worktree | working = HEAD~1 only
CODEX_JOIN_BUDGET=240                    # seconds to wait for Codex after the Claude passes return
RUN_RETENTION=20                         # run directories kept before pruning
```

- Lattice is plugin-namespaced (`/lattice:review`), so there is no collision with gstack's bare `/review`. Running both is the point — they cover different ground (standards/craft vs. structural landmines).
- **Codex runs here, not inside `/review`.** Pass B is told to skip its own Codex passes; this skill runs `codex review` itself as a fourth pass, in the background, concurrent with the others. Rationale in Pass D.
- `/cso --diff` scopes the audit to changed files and keeps daily mode's 8/10 confidence gate. High-risk diffs upgrade to `--diff --comprehensive` (Step 4).
- `REVIEW_SCOPE="branch"` matches what a human PR reviewer sees, and a Lattice `checkpoint_mode: continuous` session already has WIP commits on the branch that `working` scope would silently skip.

## Output contract

Two audiences, two artifacts. Do not confuse them.

- **Chat is for the human.** It gets the verdict on the first line and *every* finding from *every* pass, merged and triaged. It is never a pointer to a file. "Full report at `<path>`" is not an acceptable substitute for the findings themselves.
- **Disk is for the agents and for later analysis.** Raw pass reports, the diff packet, and the run log live in the run directory. Nothing there is required reading for the user.

## Token discipline

Four invariants. Every step below is built around them; violating one silently makes the run cost several times what it should.

1. **The orchestrator never loads the diff.** Step 4 classifies risk with `grep -c` over the patch and reads only the counts. The full patch enters no context but the subagents' own.
2. **Reviewers read the packet, not git.** The diff is materialized once (Step 4) and every pass is handed the same file paths. No pass re-derives scope, and no pass runs `git diff` — which also guarantees their findings are comparable.
3. **Passes return compact findings; prose goes to disk.** This is the largest saving by far. `/review` alone emits dashboards, specialist merges, and synthesis blocks running to five figures in tokens; the compact block is a few hundred. Each pass writes its full report to `$RUN_DIR/raw/` and returns only the fixed-format block in Step 5.
4. **Raw reports are not read back.** Triage runs on the compact blocks. Open a raw report only to disambiguate one specific finding, and read only that finding's section.

## Workflow

Steps run in order. Step 5 is one parallel fan-out; everything else is sequential.

### Step 1: Preflight

```bash
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "NOT_A_REPO"; exit 1; }
BRANCH=$(git branch --show-current)
DIRTY=$(git status --porcelain | wc -l | tr -d ' ')
INDEX_TREE=$(git write-tree 2>/dev/null || echo "")
GSTACK_ROOT=""
for d in "$HOME/.claude/skills/gstack" "$HOME/.gstack/repos/gstack"; do
  [ -d "$d" ] && { GSTACK_ROOT="$d"; break; }
done
GSTACK_BIN="${GSTACK_ROOT:+$GSTACK_ROOT/bin}"
HAS_GSTACK=$([ -f "$HOME/.claude/skills/review/SKILL.md" ] && [ -f "$HOME/.claude/skills/cso/SKILL.md" ] && echo 1 || echo 0)
HAS_CODEX=$(command -v codex >/dev/null 2>&1 && echo 1 || echo 0)
CODEX_CFG=$([ -x "$GSTACK_BIN/gstack-config" ] && "$GSTACK_BIN/gstack-config" get codex_reviews 2>/dev/null || echo unknown)
BASE=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || echo main)
git fetch origin "$BASE" --quiet 2>/dev/null || true
DIFF_BASE=$(git merge-base "origin/$BASE" HEAD 2>/dev/null || echo "")
if [ -n "$DIFF_BASE" ]; then
  AHEAD=$(git rev-list --count "$DIFF_BASE..HEAD")
else
  AHEAD=$(git rev-list --count @{upstream}..HEAD 2>/dev/null || echo 0)
fi
echo "BRANCH=$BRANCH DIRTY=$DIRTY AHEAD=$AHEAD BASE=$BASE DIFF_BASE=$DIFF_BASE INDEX_TREE=${INDEX_TREE:-none} GSTACK=$HAS_GSTACK CODEX=$HAS_CODEX/$CODEX_CFG"
```

`AHEAD` counts commits **not in the base branch** (`$DIFF_BASE..HEAD`) — deliberately not `@{upstream}..HEAD`. Comparing a branch against its own upstream asks the wrong question: a fully pushed PR branch reports `AHEAD=0` even though its PR diff is a hundred commits wide, and a branch with no upstream falls back to `0`. Either would stop the skill with "nothing to review" while a complete, reviewable diff sits in front of it. The `@{upstream}` form survives only as the degraded fallback for when there is no `origin/$BASE` to merge-base against.

Tool-availability accounting — state each of these up front, never silently:

- `HAS_GSTACK=0` → `/review` and `/cso` do not exist here. **Two of four passes cannot run.** Say so plainly, run Pass A and Pass D, label the verdict reduced-lens. Discovering this inside a subagent instead wastes the run and produces a report that looks complete but isn't.
- `HAS_CODEX=0` → no cross-model coverage. Say so; do not substitute a Claude pass for it.
- `CODEX_CFG=unknown` → `gstack-config` was not found, so the setting could not be read. Report unknown, never guess `enabled`. Note this only gates gstack's internal Codex, which Pass B is told to skip anyway; Pass D runs on `HAS_CODEX` alone.

Stop conditions:

- Not a git repo → tell the user and stop.
- `DIRTY=0` **and** `AHEAD=0` → nothing to review; stop.
- `DIRTY=0` but `AHEAD>0` → the branch carries commits the base does not, pushed or not. Review them: skip the checkpoint in Step 3, keep `REVIEW_SCOPE="branch"`. This is the normal shape of an open PR whose work is fully committed and pushed.
- `DIFF_BASE` empty (no `origin/$BASE`, detached, fresh repo) → fall back to `REVIEW_SCOPE="working"` and say so.
- `INDEX_TREE=none` → unmerged index; a conflict is in progress. Stop and say so. Do not checkpoint a conflicted tree — a half-merged tree is not a reviewable diff.

Record `INDEX_TREE`. Step 9 uses it to restore the index **exactly**. It is a real tree object written from the pre-review index, so it carries the staged *content* of every path, not just its name. A name list cannot do this: a partially staged file — some hunks in the index, others not — restores by re-staging the whole file, silently folding the unstaged hunks in and destroying the split the user built.

Then establish the run directory. Unlike a `mktemp` scratch dir, this persists — it is the record that makes a run analyzable afterward.

```bash
if grep -qx ".fresh-review/" .gitignore 2>/dev/null; then REPORT_DIR=".fresh-review"; else REPORT_DIR="$(git rev-parse --git-dir)/fresh-review"; fi
LOG_DIR="$(git rev-parse --git-common-dir)/fresh-review"
RUN_ID="$(date +%Y%m%d-%H%M%S)-$(echo "$BRANCH" | tr '/' '-')"
RUN_DIR="$REPORT_DIR/runs/$RUN_ID"
mkdir -p "$RUN_DIR/packet" "$RUN_DIR/raw" "$LOG_DIR"
TS_START=$(date -u +%Y-%m-%dT%H:%M:%SZ); T0=$(date +%s)
```

Never append to `.gitignore` yourself. Mutating a tracked file mid-review injects a change into the diff under review; if `.fresh-review/` is not already ignored, the git dir is the correct fallback.

`LOG_DIR` is deliberately the **common** git dir, not the per-worktree one. In a worktree `git rev-parse --git-dir` resolves to `.git/worktrees/<name>`, so an index written there would fragment across worktrees and be deleted with them — and cross-run analysis would silently see only a fraction of the history. Run directories stay local and disposable; the index in `LOG_DIR` is the durable record. Entries may therefore outlive the run directory they point at, which is expected.

### Step 2: Resolve the review scope

One canonical scope string, handed identically to every reviewer so their findings are comparable:

- `REVIEW_SCOPE="branch"` → `DIFF_CMD="git diff $DIFF_BASE"`
- `REVIEW_SCOPE="working"` → `DIFF_CMD="git diff HEAD~1"` (post-checkpoint) or `git diff HEAD`

State the resolved `DIFF_CMD` out loud. Nothing is materialized yet — the packet is built in Step 4, after the checkpoint, so that untracked files are in it.

### Step 3: WIP checkpoint

```bash
git add -A
git commit --no-verify -m "WIP: fresh-review checkpoint (will reset)" >/dev/null \
  && CHECKPOINT=committed || CHECKPOINT=failed
CHECKPOINT_SHA=$(git rev-parse HEAD)
echo "CHECKPOINT=$CHECKPOINT INDEX_TREE=$INDEX_TREE"
```

`--no-verify` bypasses pre-commit hooks — this skill IS the review.

Keep `CHECKPOINT` distinct from `INDEX_TREE`, because the two undos in Step 9 are independent. `git add -A` mutates the index whether or not the commit that follows succeeds; if the commit fails (hook escape, empty identity, locked ref) and the skill treats that as "no checkpoint, skip the restore", the `add` is never undone and the user's carefully split index is left with everything staged.

**What the checkpoint is for:** making untracked files visible. A brand-new file does not appear in `git diff` at all, so without staging it the reviewers would never see the code most likely to contain fresh bugs. It also pins a stable SHA for the audit trail and for Codex's `--commit` scoping. It does not freeze what reviewers read — they read the packet, which is why the packet is built after this point and not before.

Skip when `DIRTY=0`. On `CHECKPOINT=failed`, continue in no-checkpoint mode: build the packet from `git diff HEAD` / `git diff $DIFF_BASE`, and record in the report that untracked files went unreviewed. **Still run Step 9's index restore** — only the commit-reset half is skipped.

In no-checkpoint mode there is no clean baseline for the Step 6.5 mutation check, so take one now:

```bash
git status --porcelain > "$RUN_DIR/raw/pre-fanout.status"
```

**Do not edit anything from here until Step 9 completes.** A formatter-on-save or codegen watcher firing mid-review produces findings with stale line numbers.

### Step 4: Build the shared diff packet and classify risk

Materialize the scope **once**. Every reviewer is handed these exact paths.

```bash
$DIFF_CMD > "$RUN_DIR/packet/diff.patch"
$DIFF_CMD --stat > "$RUN_DIR/packet/stat.txt"
$DIFF_CMD --name-status > "$RUN_DIR/packet/files.txt"
FILE_COUNT=$(wc -l < "$RUN_DIR/packet/files.txt" | tr -d ' ')
```

Then classify risk **without reading the diff into context** — pattern-count only, so the orchestrator sees integers rather than a patch:

```bash
RX='auth|login|session|token|password|jwt|oauth|payment|billing|stripe|charge|refund|migration|schema|permission|authoriz|secret|credential|deserial'
PATH_HITS=$(grep -ciE "$RX" "$RUN_DIR/packet/files.txt" || true)
BODY_HITS=$(grep -ciE "$RX" "$RUN_DIR/packet/diff.patch" || true)
IAC_HITS=$(grep -ciE '\.github/workflows|Dockerfile|terraform|\.tf$|cdk|helm|k8s' "$RUN_DIR/packet/files.txt" || true)
LINES=$(grep -cE '^[+-]' "$RUN_DIR/packet/diff.patch" || true)
RISK=normal
{ [ "$PATH_HITS" -gt 0 ] || [ "$IAC_HITS" -gt 0 ] || [ "$BODY_HITS" -gt 3 ] || [ "$LINES" -gt 300 ]; } && RISK=high
{ echo "SCOPE=$REVIEW_SCOPE"; echo "DIFF_CMD=$DIFF_CMD"; echo "BASE=$BASE";
  echo "DIFF_BASE=$DIFF_BASE"; echo "CHECKPOINT=$CHECKPOINT_SHA"; echo "RISK=$RISK"; } > "$RUN_DIR/packet/scope.txt"
echo "FILES=$FILE_COUNT LINES=$LINES RISK=$RISK (path=$PATH_HITS body=$BODY_HITS iac=$IAC_HITS)"
```

The classification gates exactly one thing:

| | normal | high-risk |
|---|---|---|
| `/cso` scope | `--diff` | `--diff --comprehensive` (2/10 bar, more surfaced) |

Codex depth is deliberately *not* gated on risk — Pass D runs the structured review every time, and since it is off the critical path there is nothing to save by skipping it.

State the file count and risk class out loud. If `LINES` exceeds ~2000, warn that reviewer quality degrades at that size and that a re-run scoped to a subdirectory reads more carefully — then **proceed anyway**. This skill never blocks on a question: it is meant to run unattended, including inside `/loop`. Every branch point resolves to a default and says which default it took.

### Step 5: Fan out all reviewers (one parallel batch)

Launch the three Claude subagents **and** the Codex background command **in a single message**. Codex overlapping the others is the entire reason it stopped being a latency problem.

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

The three commands are full interactive workflows that end in *acting*, not merely reporting: `/review` auto-fixes, asks, and applies; `/cso` ends in a remediation conversation; `/lattice:review` ends by writing to a tracked file. A generic "be non-interactive and read-only" in the isolation contract does not reliably beat a nested skill's own numbered steps — the subagent is reading that skill as executable instructions, and the last instruction it reads wins. So each pass below names the specific sub-steps to skip, *by their heading*, and Step 6.5 verifies the outcome mechanically rather than trusting the prompt. Both are needed: the prompt sets intent, the check catches the miss.

Two clarifications on the non-interactive lever, since it is easy to reach for the wrong one:

- `SPAWNED_SESSION: true` is the mode we want. gstack's own spawned-session block ("Skill routing" in `~/.claude/skills/{review,cso}/SKILL.md`) tells the skill to auto-choose the recommended option instead of calling AskUserQuestion.
- **Do not set `GSTACK_HEADLESS`.** It classifies the session as `headless`, and gstack's AskUserQuestion-failure fallback maps `headless` to `BLOCKED — stop and wait` (`~/.claude/skills/gstack/bin/gstack-session-kind`). That is the opposite of unattended: it would hang the pass on the first question rather than defaulting past it.

Then append the pass-specific task:

**Pass A — lattice** (`{{LATTICE_REVIEW_CMD}}`)
> Run `{{LATTICE_REVIEW_CMD}}` against the packet. Apply atoms conditionally: clean-code always; architecture, DDD, secure-coding, test-quality only when the delta touches their domain.
> **Stop after its "Step 4: Produce Report". Do not run "Step 5: Harvest Learnings and Log Review."** That step asks the user to confirm which learnings enter the document and then writes them to `.lattice/learnings/operational-learnings.md` — a tracked file, so it would inject a change into the very diff under review *and* block on a question no human is there to answer. Harvesting learnings from this review is the producer's job, after triage.

**Pass B — gstack review** (`{{GSTACK_REVIEW_CMD}}`) — substitute `{{RISK}}` and `{{CODEX_AVAILABLE}}` from Step 1 and Step 4; the dispatch table below branches on both.
> Context for your dispatch decisions: this review is **{{RISK}}**-risk, and cross-model Codex coverage is **{{CODEX_AVAILABLE}}**.
>
> Run `{{GSTACK_REVIEW_CMD}}`, but **only its analysis steps**. Skip these entirely, they are either destructive here or already covered:
> - **Step 1.5 Scope Drift Detection, Plan File Discovery, and Fallback Intent Sources.** These read plan files, `TODOS.md`, and the PR body specifically to establish "stated intent" — a direct violation of your isolation contract. You have no intent to compare against, and that is deliberate.
> - **Step 5 Fix-First Review** in all its parts (classify/auto-fix/batch-ask/apply). You must not modify code.
> - Greptile triage and comment resolution, Step 5.5 TODOS cross-reference, Step 5.6 documentation staleness.
> - **Step 5.7's Codex passes.** fresh-review runs Codex itself as a separate parallel pass; running them here would pay for the same cross-model coverage twice, serially, on the critical path.
>
> Keep the Step 4 critical pass, Step 4.6 merge, and a controlled subset of the dispatches. Left alone, this pass fans out to **nine nested subagents** (seven specialists + Red Team + the adversarial subagent), most of them duplicating another fresh-review pass. Dispatch exactly this:
>
> | Dispatch | Run? | Why |
> |---|---|---|
> | `security` | **yes** | `/cso` runs with an 8/10 confidence gate (2/10 comprehensive); this one has no gate and surfaces what that drops. gstack tags it `[NEVER_GATE]`. |
> | `performance` | **yes** | No other pass covers it. |
> | `data-migration` | **yes** | No other pass covers it. Also `[NEVER_GATE]`. |
> | `api-contract` | **yes** | No other pass covers breaking contract changes. |
> | **Red Team** | **yes** | Second-order and the best-aligned dispatch here: it receives the merged specialist findings and hunts for what they *missed*, on cross-cutting and integration-boundary failures. Anti-correlated with every other pass by construction, which is exactly this skill's purpose. |
> | `testing` | no | Duplicates Pass A's lattice `test-quality` atom. |
> | `maintainability` | no | Duplicates Pass A's `clean-code` atom, and contradicts the instruction below to skip clean-code findings. |
> | `design` | no | UX/visual checklist, out of this skill's charter — `/design-review` is the tool for that. |
> | Claude adversarial subagent (Step 5.7) | **only if told Codex is unavailable** | Same model and same adversarial framing as Red Team, and Pass D already covers adversarial cross-model. It reverts to its documented fallback role rather than running as a third correlated adversarial lens. |
>
> Force the four specialists with `--security --performance --data-migration --api-contract` and dispatch nothing else. Do not rely on Step 4.5's adaptive gating to prune anything — `gstack-specialist-stats` reports `0 reviews analyzed`, so `[GATE_CANDIDATE]` never fires and scope gating is the only filter that actually operates.
>
> **Red Team activation:** its stock trigger is `DIFF_LINES > 200` or any specialist CRITICAL. Suppressing three specialists lowers the odds of the CRITICAL path firing, so force Red Team whenever this review is high-risk — I will tell you the risk class — and otherwise leave its condition alone.
>
> Every specialist prompt, and Red Team's, tells the subagent to run `git merge-base` and `git diff` itself. Override that: point all of them at `{{RUN_DIR}}/packet/diff.patch`, so five nested subagents don't each re-derive the same diff.
>
> Focus on structural landmines: SQL safety, LLM trust boundaries, conditional side effects, data migrations, unbounded queries, missing input validation, hidden coupling, breaking API changes. Skip pure clean-code style findings — that is Pass A's territory.
>
> In your compact block, prefix each finding's category slug with the specialist that raised it (`security/…`, `api-contract/…`) so triage can tell correlated sources apart.

**Pass C — cso** (`{{CSO_CMD}}`, plus `--comprehensive` when high-risk)
> Run `{{CSO_CMD}}`. Honor its confidence gate — do not report below it. Cover OWASP/STRIDE on the changed surface, secrets, dependency and CI/CD exposure introduced by this diff. Give each finding a concrete exploit path in the problem field. If nothing clears the gate, return `FINDINGS: 0` — do not pad.
> **Run through "Phase 12: False Positive Filtering + Active Verification", then report and stop.** From "Phase 13: Findings Report + Trend Tracking + Remediation", produce the findings report only — no remediation planning, no remediation questions, no patches. State each fix in one sentence and let the producer decide.

**Pass D — Codex** (background Bash, launched in the same message, not a subagent)

```bash
( codex review --base "$BASE" \
    -c sandbox_mode="read-only" -c approval_policy="never" \
    -c 'model_reasoning_effort="high"' \
    < /dev/null > "$RUN_DIR/raw/codex.md" 2> "$RUN_DIR/raw/codex.err"
  echo $? > "$RUN_DIR/raw/codex.rc" ) 
```

Use `run_in_background: true`. Never set a Bash `timeout` on this — a timeout is a hard kill that burns the full budget and discards the work. Backgrounding makes the budget a *join deadline* instead, and the harness re-invokes you when the command exits.

Four things about this invocation are deliberate:

- **`codex review`, not `codex exec`.** `review` scopes natively and emits structured, severity-marked findings that drop into the triage table. `exec` returns prose that would have to be parsed. gstack uses `exec` unconditionally and gates `review` at 200+ lines as its own cost control; that gating does not bind us once Codex is off the critical path.
- **`--base`, and therefore no custom prompt.** The CLI rejects `[PROMPT]` together with `--base` (`error: the argument '[PROMPT]' cannot be used with '--base <BRANCH>'`), so the isolation contract cannot be injected. `--base` still wins: a separate process running a different model family with no conversation history is the strongest isolation of any pass here, and handing it the base branch avoids spending agentic turns rediscovering the diff. For `REVIEW_SCOPE="working"`, use `--commit "$CHECKPOINT_SHA"` instead.
- **`approval_policy="never"` and `sandbox_mode="read-only"`.** A non-interactive background run that stalls on an approval prompt is indistinguishable from a slow one. Read-only also enforces "do not fix anything" at the process level rather than by instruction.
- **No `--enable web_search_cached`.** gstack enables it; for a diff review it rarely pays and it adds latency.

Budget expectations: measured floor is ~30s on an *empty* diff (process start, git probe, one model round trip). Real diffs run minutes. That floor is why Codex must never gate the verdict.

### Step 6: Join and isolation audit

When the three Claude passes have returned, check Codex once:

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

Self-reporting is the only audit available for *reads* — a parent agent cannot inspect a subagent's tool trace, and it cannot see a `gh pr view` call at all, which is why Pass B is told to skip the intent-gathering steps rather than merely warned about them. Treat this as a smoke detector, not a guarantee. (Step 6.5 is the one part of the contract that *is* mechanically verified; reads are not.)

**Pass B is the expected offender.** Its workflow natively hunts for intent — plan files, `TODOS.md`, the PR body, commit messages — so a leak there means the Step 1.5 skip did not take, not that the reviewer went rogue. Check its `FILES_READ` for those paths specifically. If they appear, Pass B is intent-aware for this run: keep its structural findings, but discard any "this is intentional / matches the plan" conclusion it drew, and say so in the report rather than quietly inheriting its verdict.

### Step 6.5: Reviewer mutation check (read-only enforcement)

The prompt asked the reviewers not to write. This verifies it, because a subagent inherits the parent's tool access — there is no per-call tool restriction to lean on, and `/review`'s auto-fix is a documented part of the workflow it was told to run.

The Step 3 checkpoint committed everything, so the tree was clean when the fan-out started. Any dirt now came from a reviewer:

```bash
git status --porcelain > "$RUN_DIR/raw/post-fanout.status"
if [ "$CHECKPOINT" = committed ]; then LEAK=$(cat "$RUN_DIR/raw/post-fanout.status")
else LEAK=$(diff "$RUN_DIR/raw/pre-fanout.status" "$RUN_DIR/raw/post-fanout.status" || true); fi
[ -n "$LEAK" ] && printf 'REVIEWER_WROTE_TO_TREE\n%s\n' "$LEAK"
```

If it fires:

```bash
mkdir -p "$RUN_DIR/quarantine"
git diff HEAD > "$RUN_DIR/quarantine/reviewer-edits.patch"
git restore --source=HEAD --worktree -- .
git status --porcelain --untracked-files=all
```

- **Tracked files** revert to the checkpoint. Their content is committed, so nothing is lost.
- **Untracked files** are only *listed*, never cleaned. `git clean` here could delete real work — a build artifact, a watcher's output, or a file the user created a second ago. Report the paths and let them decide.
- Record the violation and treat that pass's findings as still valid but its judgment as suspect: a reviewer that ignored "do not fix" may have ignored the forbidden-reads list too.

In no-checkpoint mode the baseline is the Step 3 snapshot and the check is a diff of the two status files. **Do not auto-revert there** — the producer's own uncommitted work is interleaved with the reviewer's, and `git restore` cannot tell them apart. Print the delta, name the suspect paths, hand it to the user.

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
  | `codex` + any Claude pass | different model family, separate process, no shared context | **strongest** — treat as near-confirmed; bucket 2 needs an explicit citation |
  | `gstack/red-team` + any specialist | Red Team was *shown* the specialist findings and told to find what they missed | **strongest** — it converged despite being steered away from that ground, so it found the issue independently |
  | `cso` + `gstack/security` | same model, but different confidence gates and different checklists | moderate |
  | `lattice` + `gstack` on a craft finding | same model running similar checklists | **weak** — one reviewer twice, not two reviewers; it blocks bucket 3 but is not positive evidence of a real bug |

  This is why Pass B tags findings with the specialist that raised them: `lattice` agreeing with `gstack/api-contract` is meaningful, while `lattice` agreeing with `gstack/maintainability` would have been the same clean-code checklist counted twice — which is also why that specialist is suppressed.

Write the merged pre-triage findings to `$RUN_DIR/findings.tsv` for the log.

### Step 8: Report to chat

**This is the primary output.** Print it in full, in chat, in this shape. Verdict first, always.

```
FRESH REVIEW — <COMMIT | COMMIT-WITH-FIXES | DO-NOT-COMMIT>
<branch> · <N> files, +<a>/−<b> · risk: <normal|HIGH> · <elapsed>
passes: lattice <✓n|✗>  gstack <✓n|✗>  cso <✓n|✗>  codex <✓n|⧗ running|✗ reason>

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
- **Every finding from every pass appears here**, in one of the four buckets. Deduplicated, with its sources tagged, but never dropped and never deferred to the report file. A bucket with zero findings collapses to a single `BY DESIGN (0)` line.
- Blockers get the full two-line treatment. The other three buckets get one line each.
- `[<sources>]` is the merged source list (`lattice`, `gstack`, `cso`, `codex`) — this is how the user sees which passes converged, which is the signal the cross-model rule is built on.
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

### Step 8.6: Hand the triage to `/ship` (suppression handoff)

**Run before Step 9** — it needs the checkpoint SHA, which the reset destroys.

`/ship` always re-runs its own pre-landing review. That is unconditional and not configurable — gstack's `skip_eng_review` only flips the verdict on ship's Review Readiness Dashboard, it does not skip the review. What *is* avoidable is being asked about the same findings twice: ship's **"Cross-review finding dedup"** step suppresses any finding whose fingerprint was logged with `action: "skipped"` on this branch, provided that file has not changed since the logged commit.

(Those behaviors live in the external gstack install: `~/.claude/skills/ship/SKILL.md` and `~/.claude/skills/gstack/ship/sections/review-army.md`. Named by section rather than line number because line numbers drift on every `gstack-upgrade`.)

```bash
STATUS="clean"        # or "issues_found" if any REAL BUG was triaged
FINDINGS='[{"fingerprint":"path/to/file.py:42:security","severity":"CRITICAL","action":"skipped"}]'
"$GSTACK_BIN/gstack-review-log" \
  "{\"skill\":\"fresh-review\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"status\":\"$STATUS\",\"commit\":\"$CHECKPOINT_SHA\",\"branch\":\"$BRANCH\",\"verdict\":\"$VERDICT\",\"findings\":$FINDINGS}"
echo "HANDOFF_RC=$?"
```

Rules for the `findings` array:

- **Only buckets 2, 3, and 4**, each as `action: "skipped"`. Those are the decisions worth carrying forward.
- **Never log a bucket 1 (REAL BUG) finding.** Omitting it is deliberate: ship re-reviews it, which is the regression check on your fix. Logging it as `skipped` would suppress the one finding you most need re-verified.
- `fingerprint` is exactly `path:line:category` — repo-relative path, the finding's line, the category slug lowercased. A wrong fingerprint simply fails to match and the finding resurfaces in ship. **This step fails safe in that direction**: the worst outcome is answering a review question twice, never a real bug being hidden.
- `status` is `"clean"` only when bucket 1 is empty.

Capture `HANDOFF_RC` into the run log. This handoff has silently no-op'd in past runs and the absence of a recorded exit code is exactly why that went unnoticed. If it exits non-zero (malformed JSON, `bun` missing, no gstack install), continue and say so in chat — it is a convenience, never a gate.

Two things this does **not** do: it does not stop ship's pre-landing review from running, and it does not flip the Eng Review row on ship's readiness dashboard — that row only reads entries from skills named `review` or `plan-eng-review`, and Pass B's own `/review` entry is what satisfies it.

In no-checkpoint mode, still write the entry but expect no suppression: the logged commit is the pre-existing HEAD, so every file you later commit reads as "changed since the review".

### Step 9: Restore working state

Regardless of verdict, undo the checkpoint and restore the original index. **Two independent undos:**

```bash
[ "$CHECKPOINT" = committed ] && git reset --soft HEAD~1    # 1. drop the checkpoint commit
[ -n "$INDEX_TREE" ] && git read-tree "$INDEX_TREE"         # 2. restore the exact pre-review index
git status --short
```

`git read-tree` replaces the index with the tree recorded in Step 1 and does not touch the worktree, so the staged/unstaged split comes back exactly as it was — including partially staged files, which a re-`git add` by filename would have flattened into fully staged.

Run **2** whenever `INDEX_TREE` is set and Step 3 ran `git add -A`, **including when `CHECKPOINT=failed`**. That is the case a "skip the restore in no-checkpoint mode" rule gets wrong: `add` had already staged everything, and skipping the restore leaves it that way. Run **1** only when the commit actually landed — resetting after a failed commit would throw away the user's last real commit.

Skip both only when Step 3 was skipped outright (`DIRTY=0`): nothing was staged and nothing was committed, so there is nothing to undo.

Then tell the user: "Working tree restored — staged/unstaged split is back as it was."

This must run even on abort or error. If the user interrupts mid-review, restoring the tree is the first thing you do on the next turn.

### Step 10: Persist the run log

Write `$RUN_DIR/report.md` (the Step 8 chat output verbatim, plus scope, pass inventory, and isolation-audit result), then append one line to the index and prune:

```bash
T1=$(date +%s)
cat > "$RUN_DIR/run.json" <<JSON
{"skill":"fresh-review","schema":2,"run_id":"$RUN_ID",
 "ts_start":"$TS_START","ts_end":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","duration_s":$((T1-T0)),
 "repo":"$(basename "$(git rev-parse --show-toplevel)")","branch":"$BRANCH","base":"$BASE",
 "scope":"$REVIEW_SCOPE","diff_base":"$DIFF_BASE","checkpoint":"$CHECKPOINT_SHA","risk":"$RISK",
 "diff":{"files":$FILE_COUNT,"lines":$LINES},
 "passes":[
   {"name":"lattice","status":"ok","duration_s":0,"findings":0,"isolation":"clean"},
   {"name":"gstack","status":"ok","duration_s":0,"findings":0,"isolation":"clean"},
   {"name":"cso","status":"ok","duration_s":0,"findings":0,"isolation":"clean"},
   {"name":"codex","status":"ok","duration_s":0,"findings":0,"changed_verdict":false}],
 "triage":{"real_bug":0,"by_design":0,"noise":0,"misread":0,"deduped":0},
 "verdict":"$VERDICT","handoff_rc":$HANDOFF_RC,
 "tools":{"gstack":$HAS_GSTACK,"codex":$HAS_CODEX}}
JSON
python3 -c "import json,sys;print(json.dumps(json.load(open(sys.argv[1]))))" "$RUN_DIR/run.json" >> "$LOG_DIR/runs.jsonl"
[ -n "$REPORT_DIR" ] && [ -d "$REPORT_DIR/runs" ] && \
  ls -1dt "$REPORT_DIR"/runs/*/ 2>/dev/null | tail -n +$((RUN_RETENTION+1)) | xargs -r rm -rf
"$GSTACK_BIN/gstack-timeline-log" "{\"skill\":\"fresh-review\",\"event\":\"completed\",\"branch\":\"$BRANCH\",\"outcome\":\"$STATUS\",\"duration_s\":\"$((T1-T0))\"}" 2>/dev/null || true
```

Fill the zeroed fields from the actual run — per-pass wall time, per-pass finding counts, and the triage bucket counts. Those are the point of the log, not decoration.

The `python3` round-trip both validates the JSON and flattens it to one line; if it fails, the line is malformed and must not be appended — a corrupt `runs.jsonl` breaks every future analysis of it.

**What this log is for.** Three questions it is designed to answer across runs, none of which are answerable today:

- *Where does the time actually go?* Per-pass `duration_s` replaces the impression that "the run is slow" with the name of the pass that is slow.
- *Is Codex earning its place?* `codex.duration_s` against `codex.changed_verdict` over a dozen runs is the evidence for keeping or dropping it.
- *Which pass produces noise?* A pass whose findings land overwhelmingly in buckets 3 and 4 is miscalibrated for this repo and should be re-scoped or dropped.

Schema is versioned (`schema:2`) and the shape is deliberately generic — `skill`, `run_id`, `duration_s`, `passes[]`, `verdict` — so a future cross-skill run-analysis tool can read it alongside other skills' logs without a per-skill parser.

## Failure modes and recovery

- **Checkpoint commit fails** (`CHECKPOINT=failed`) → no-checkpoint mode (Step 3), document it, and **still run Step 9's `git read-tree "$INDEX_TREE"`** — `git add -A` already ran, so the index needs restoring even though there is no commit to reset.
- **Unmerged index** (`INDEX_TREE=none`) → stop at preflight. Resolve the conflict, then re-run.
- **A pass returns nothing / errors** → log it as skipped and continue. No single pass is blocking, but the verdict must name the absent lens.
- **A pass ignores the compact return contract** and dumps prose → do not re-read it; note it in NOTES, extract findings from its `raw/` file with a compactor subagent as in Step 6.
- **Codex times out / fails** → verdict ships Claude-only, `CODEX_FAILED` in the log. Never substitute a Claude pass for it. Fix is `codex login` and re-run.
- **Subagent tries to fix code** → Step 6.5 catches and reverts it. This is an expected failure mode, not a rare one: `/review`'s auto-fix is part of the workflow the reviewer was told to run.
- **User aborts midway** → Step 9 first, then report what was collected.
- **Forbidden read detected** → Step 6 handles it: note, downgrade confidence, optionally re-spawn.
- **`runs.jsonl` fails to validate** → drop the line, keep `$RUN_DIR/run.json`, tell the user the index entry was skipped.

## What this skill does NOT do

- **Open a literal fresh Claude Code session.** For maximum isolation before a major release: `git worktree add ../review-wt HEAD`, start Claude Code there, run the three commands manually.
- **Auto-apply fixes.** The calling session applies fixes after triage. This skill only diagnoses.
- **Replace a full security audit.** `/cso --diff` covers the changed surface only. A full `/cso` remains a periodic job.
- **Replace QA.** Nothing here proves the code runs. `/qa` still applies.
- **Run the CI gates.** Tests, coverage, and lint are `/ship`'s job. A `COMMIT` verdict says the code reads correctly, not that it passes.
- **Stop `/ship` from reviewing again.** Ship's pre-landing review is unconditional and reviews the *final* diff — post-fix, post-CHANGELOG, post-base-merge — a different artifact from what these passes saw. Step 8.6 makes that pass quiet rather than absent.
- **Analyze runs across sessions.** The log is written to be analyzable; reading it is a separate tool's job.

## Examples

**"fresh review my changes before I commit"** → Steps 1–10; branch-scoped packet built once; three isolated subagents plus Codex in background, all launched together; verdict and every finding printed to chat; tree restored; run logged. No questions asked at any point.

**"review this before I push"** with `auth/` in the diff → Step 4 classifies high-risk on `PATH_HITS`; `/cso` upgrades to `--diff --comprehensive`; four sources triaged under the security floor.

**Codex still running when the Claude passes return** → verdict prints as `codex ⧗ running`; the background task completes eight minutes later; Step 8.5 posts the addendum and records whether it moved the verdict.
