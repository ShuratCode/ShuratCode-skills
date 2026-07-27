---
name: fresh-review
description: |
  Pre-commit fresh-eyes code review. Orchestrates a context-isolated review pass that approximates what
  a new reviewer would catch — runs the lattice review, the gstack review, and the gstack security audit
  against the current diff via subagents that cannot read design docs, intent, or prior session context.
  Cross-model Codex coverage comes free inside the gstack review. Triages findings against the
  producer-context and outputs a merge recommendation.

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

When you design, write, and review code in the same session, the reviewer-Claude already agrees with the design choices and knows the rationale. It rationalizes away its own decisions. Real review needs the reviewer to *lack* context the producer has. This skill enforces that separation by spawning subagents with strict context restrictions, adding a cross-model reviewer, and then triaging their findings back in the producer context (where intent is known and "by design" can be properly justified).

## Configuration

Slash-command names and scope, configured here. Edit if your install differs.

```
LATTICE_REVIEW_CMD="/lattice:review"     # Lattice standards conformance (plugin-namespaced)
GSTACK_REVIEW_CMD="/review"              # gstack pre-landing review — carries Codex internally
CSO_CMD="/cso --diff"                    # gstack security audit, scoped to branch changes
REVIEW_SCOPE="branch"                    # branch = merge-base..worktree | working = HEAD~1 only
```

Notes on these choices:

- Lattice is plugin-namespaced (`/lattice:review`), so there is no longer a name collision with gstack's bare `/review`. Running both is safe and is the point of this skill — they cover different ground (standards/craft vs. structural landmines).
- **There is no separate `/codex` pass, on purpose.** `/review` already runs Codex itself: a `codex exec` adversarial challenge on every diff when Codex is ready, plus a `codex review` structured pass at 200+ changed lines, with a Claude adversarial subagent as the fallback when Codex is missing, unauthenticated, or disabled. Invoking `/codex` separately would pay for the same cross-model pass twice. What this skill does instead is verify Codex actually ran and surface its findings as their own triage source.
- `/cso --diff` scopes the audit to files changed on this branch and keeps daily mode's 8/10 confidence gate, so it stays a pre-commit gate rather than a monthly infra sweep. High-risk diffs upgrade to `--diff --comprehensive` (see Step 3).
- `REVIEW_SCOPE="branch"` is the default because it matches what a human PR reviewer actually sees, and because a Lattice `checkpoint_mode: continuous` session already has WIP commits on the branch — `working` scope would silently skip them.

## Workflow

Run steps in order. Step 5 is one parallel fan-out; everything else is sequential.

### Step 1: Preflight

```bash
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "NOT_A_REPO"; exit 1; }
BRANCH=$(git branch --show-current)
DIRTY=$(git status --porcelain | wc -l | tr -d ' ')
AHEAD=$(git rev-list --count @{upstream}..HEAD 2>/dev/null || echo 0)
STAGED_BEFORE=$(git diff --cached --name-only | tr '\n' '|')
GSTACK_ROOT=""
for d in "$HOME/.claude/skills/gstack" "$HOME/.gstack/repos/gstack"; do
  [ -d "$d" ] && { GSTACK_ROOT="$d"; break; }
done
GSTACK_BIN="${GSTACK_ROOT:+$GSTACK_ROOT/bin}"
HAS_GSTACK=$([ -f "$HOME/.claude/skills/review/SKILL.md" ] && [ -f "$HOME/.claude/skills/cso/SKILL.md" ] && echo 1 || echo 0)
CODEX_CFG=$([ -x "$GSTACK_BIN/gstack-config" ] && "$GSTACK_BIN/gstack-config" get codex_reviews 2>/dev/null || echo unknown)
HAS_CODEX=$(command -v codex >/dev/null 2>&1 && echo 1 || echo 0)
BASE=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || echo main)
git fetch origin "$BASE" --quiet 2>/dev/null || true
DIFF_BASE=$(git merge-base "origin/$BASE" HEAD 2>/dev/null || echo "")
echo "BRANCH=$BRANCH DIRTY=$DIRTY AHEAD=$AHEAD BASE=$BASE DIFF_BASE=$DIFF_BASE GSTACK=$HAS_GSTACK CODEX=$HAS_CODEX/$CODEX_CFG"
```

Tool-availability accounting — state each of these up front, never silently:

- `HAS_GSTACK=0` → `/review` and `/cso` do not exist on this machine. **Two of the three passes cannot run.** Say so plainly, run Pass A alone, and label the verdict single-lens; discovering this inside a subagent instead wastes the run and produces a report that looks complete but isn't.
- `CODEX_CFG=unknown` → `gstack-config` was not found at `$GSTACK_BIN`, so the Codex setting could not be read. Report it as unknown, not as enabled. An honest "unknown" is the whole point; guessing `enabled` and then finding no Codex output is indistinguishable from Codex silently no-opping.
- `HAS_CODEX=0` or `CODEX_CFG=disabled` → "Cross-model coverage unavailable — the gstack pass will fall back to its Claude adversarial subagent."

Never substitute anything for a missing tool; just record which lenses actually ran so the verdict is honest.

Stop conditions:

- Not a git repo → tell the user and stop.
- `DIRTY=0` **and** `AHEAD=0` → nothing to review; stop.
- `DIRTY=0` but `AHEAD>0` → there is committed-but-unpushed work. Review it: skip the WIP checkpoint in Step 4 and Step 8, and use `REVIEW_SCOPE="branch"`.
- `DIFF_BASE` empty (no `origin/$BASE`, detached, or fresh repo) → fall back to `REVIEW_SCOPE="working"` and say so in the report.

Record `STAGED_BEFORE` — Step 8 uses it to restore the exact index state.

Report directory:

```bash
if grep -qx ".fresh-review/" .gitignore 2>/dev/null; then REPORT_DIR=".fresh-review"; else REPORT_DIR="$(git rev-parse --git-dir)/fresh-review"; fi
RAW_DIR=$(mktemp -d "${TMPDIR:-/tmp}/fresh-review.XXXXXX")
mkdir -p "$REPORT_DIR"
```

Never append to `.gitignore` yourself. Mutating a tracked file mid-review injects a change into the very diff under review; if `.fresh-review/` is not already ignored, write to the git dir instead.

### Step 2: Resolve the review scope

One canonical scope string, handed identically to every reviewer so their findings are comparable:

- `REVIEW_SCOPE="branch"` → `DIFF_CMD="git diff $DIFF_BASE"` (after the Step 4 checkpoint this covers every commit on the branch plus what was uncommitted)
- `REVIEW_SCOPE="working"` → `DIFF_CMD="git diff HEAD~1"` (post-checkpoint) or `git diff HEAD` (no-checkpoint fallback)

State the resolved `DIFF_CMD` and the file count out loud before fanning out. If the diff exceeds ~2000 changed lines, warn that reviewer quality degrades on diffs this size and that a re-run scoped to a subdirectory will read more carefully — then **proceed anyway**. This skill never blocks on a question: it is meant to run unattended, including inside `/loop`, so a prompt here would hang the whole pass. Every branch point resolves to a default and says which default it took.

### Step 3: Risk assessment

Read the diff (`git diff --stat` plus the diff itself) and classify as **high-risk** if it touches any of:

- Auth/login/session/token/password/JWT/OAuth
- Payment/billing/stripe/charge/refund
- Database migrations or schema changes
- Permission or authorization logic
- IaC / deploy pipelines / CI workflow files / secrets handling
- Trust boundaries (input validation, deserialization, anything accepting external data)
- More than 300 lines changed

Otherwise **normal**. The classification gates the depth of two passes:

| | normal | high-risk |
|---|---|---|
| `/cso` scope | `--diff` | `--diff --comprehensive` (2/10 bar, more surfaced) |
| gstack Codex depth | whatever the diff size triggers | force the structured `codex review` too |

The Codex row works through `/review`'s own override: it runs the structured `codex review` only at 200+ changed lines *unless* the caller explicitly asks for a "full review" / "structured review" / "P1 gate". So a high-risk 40-line auth change gets the full treatment by wording Pass B's prompt that way. No user prompt is needed anywhere in this skill — it runs unattended end to end.

### Step 4: WIP checkpoint

```bash
git add -A
git commit --no-verify -m "WIP: fresh-review checkpoint (will reset)" >/dev/null
```

`--no-verify` bypasses pre-commit hooks — this skill IS the review.

**What the checkpoint is for:** making untracked files visible. A brand-new file does not appear in `git diff` at all, so without staging it the reviewers would never see the code most likely to contain fresh bugs. It also pins a stable SHA for the report's audit trail. It does **not** freeze what the reviewers read — they open files from the live worktree. (`git add -N .` would achieve the untracked-file visibility with a lighter touch; the commit is kept because Step 8 already restores the index exactly and a commit is easier to reason about.)

Skip this step when `DIRTY=0` (nothing to stage). If the commit fails for any other reason, continue in no-checkpoint mode: use `git diff HEAD` / `git diff $DIFF_BASE` against the live worktree, skip Step 8, and note the deviation in the report — including that untracked files went unreviewed.

**Do not edit anything from here until Step 8 completes.** The reviewers read the live worktree; a file that changes underneath them produces findings with stale line numbers, and a formatter-on-save or codegen watcher can do this without you noticing.

### Step 5: Fan out all reviewers (one parallel batch)

Launch all three reviewers as subagents **in a single message** so they run concurrently: lattice, gstack review (which carries Codex), cso.

Every subagent prompt opens with this **isolation contract**, verbatim:

> Fresh-eyes pre-commit review. You have no prior context. That is intentional and required.
>
> **Scope**: `{{DIFF_CMD}}` and the source files that diff touches.
>
> **Forbidden reads** — do not open these even if they look relevant: `.lattice/requirements/**`, `.lattice/contexts/**`, `.lattice/reviews/**`, `*.plan.md`, `*.design.md`, `docs/decisions/**`, `ONBOARDING.md`, any PR/issue body, and any file whose purpose is to record intent rather than behavior. Allowed: `.lattice/standards/**`, `.lattice/config.yaml`, `AGENTS.md`/`CLAUDE.md`, and the diffed source.
>
> **Do not infer author intent** from commit messages, docstrings, TODOs, or comments. Judge the code on its observable behavior alone. "The comment says it's fine" is not evidence.
>
> **Non-interactive**: no human is attached to your session. Never call AskUserQuestion and never wait for input — pick the reasonable default, state the assumption inline, and continue.
>
> **Do not fix anything.** No Edit, no Write to source, no commits. Diagnose only.
>
> **Last line of your output must be** `FILES_READ: <comma-separated paths>` — the full list of files you opened. This is the isolation audit.

Then append the pass-specific task:

**Pass A — lattice** (`{{LATTICE_REVIEW_CMD}}`)
> Run `{{LATTICE_REVIEW_CMD}}`. Apply atoms conditionally: clean-code always; architecture, DDD, secure-coding, test-quality only when the delta touches their domain.
> Output: severity-ordered findings only, no preamble. Per finding: severity, `file:line`, problem in one sentence, fix in one sentence.

**Pass B — gstack review** (`{{GSTACK_REVIEW_CMD}}`) — this is also the Codex pass
> Run `{{GSTACK_REVIEW_CMD}}`. It computes its own merge-base diff — expected, and it should match `{{DIFF_CMD}}`; if it does not, say so at the top of your report.
> [high-risk only] Treat this as a **full structured review / P1 gate** so the structured Codex pass runs regardless of diff size.
> Focus on structural landmines: SQL safety, LLM trust boundaries, conditional side effects, data migrations, unbounded queries, missing input validation, hidden coupling, breaking API changes. Skip pure clean-code style findings — that is Pass A's territory.
> **Report Codex separately.** This skill relies on you for cross-model coverage, so your report must contain a `## CODEX` section stating which Codex passes actually executed (adversarial `codex exec`, structured `codex review`, or neither) and their findings verbatim, kept distinct from your own Claude-side findings. If Codex was skipped or fell back to the Claude adversarial subagent, write exactly `CODEX_NOT_RUN: <reason>` — never present Claude output as Codex output. Codex is best-effort on macOS (gstack issue #2091, BSD `mktemp`) and can silently no-op; an empty result is `CODEX_NOT_RUN: empty response`.
> Output: merge/block recommendation first, then blockers (must-fix), then warnings, then the `## CODEX` section.

**Pass C — cso** (`{{CSO_CMD}}`, plus `--comprehensive` when high-risk)
> Run `{{CSO_CMD}}`. Honor its confidence gate — do not report below it. Cover OWASP/STRIDE on the changed surface, secrets, dependency and CI/CD exposure introduced by this diff.
> Output: findings with severity + `file:line` + concrete exploit path. If you find nothing at or above the gate, say `NO FINDINGS AT GATE` — do not pad.

Save each report verbatim to `$RAW_DIR/{lattice,gstack,cso}.md`.

### Step 6: Isolation audit

Check each report's `FILES_READ:` line against the forbidden list.

- Clean → proceed.
- A forbidden path appears → note the leak in the triage report and downgrade that pass's confidence (its "by design" concessions are now suspect, not its bug findings). Re-spawn only if the leak looks material and the pass is cheap.
- `FILES_READ:` missing → treat as unverified isolation, note it, and proceed. Do not re-run on this alone.

Self-reporting is the only audit available here — a parent agent cannot inspect a subagent's tool trace. Treat it as a smoke detector, not a guarantee.

### Step 7: Triage

Read all reports. Treat Pass B's `## CODEX` section as its own source (`codex`), separate from `gstack` — that separation is what makes the cross-model-agreement rule below meaningful.

You are back in the producer context with full knowledge of design intent. Deduplicate across passes (same `file:line` + same root cause = one finding, sources merged) and assign each to exactly one bucket:

1. **REAL BUG** — must fix before commit. State the fix in one sentence.
2. **REAL BUT BY DESIGN** — cite the specific decision from this session, or the specific standard/doc, that makes it intentional. No citation → reclassify as REAL BUG. Non-negotiable: this is what stops the producer from rationalizing.
3. **STYLISTIC / NOISE** — one sentence on why it doesn't matter here.
4. **REVIEWER MISUNDERSTOOD** — what they got wrong. Use sparingly; bias hard against this bucket. It is the escape hatch the producer-Claude reaches for.

Two overrides:

- **Security floor**: a `/cso` finding at HIGH or CRITICAL cannot go to bucket 3 or 4 without naming the specific compensating control (the code path, config, or middleware that neutralizes it) and where it lives. Absent that, it is a REAL BUG.
- **Cross-model agreement**: any finding raised independently by two or more passes cannot be bucket 3. Two reviewers converging without shared context is signal — and Claude-plus-Codex convergence especially so, since it survives a model-family change.

Output one triage table: finding | source(s) (`lattice` / `gstack` / `codex` / `cso`) | bucket | one-sentence justification.

Then a verdict line — exactly one of:

- `COMMIT` — no blockers
- `COMMIT-WITH-FIXES` — REAL BUG fixes listed inline, ordered by file
- `DO-NOT-COMMIT` — why, and what to do instead

### Step 7.5: Hand the triage to `/ship` (suppression handoff)

**Run this before Step 8** — it needs the checkpoint SHA, which the reset destroys.

`/ship` always re-runs its own pre-landing review. That is unconditional and not configurable — gstack's `skip_eng_review` setting only flips the verdict on ship's Review Readiness Dashboard, it does not skip the review itself. What *is* avoidable is being asked about the same findings twice: ship's **"Cross-review finding dedup"** step suppresses any finding whose fingerprint was logged with `action: "skipped"` on this branch, as long as that file has not changed since the logged commit. Writing your triage there is what makes the second review surface only what is new.

(Those behaviors live in the external gstack install, not this repo: `~/.claude/skills/ship/SKILL.md` and `~/.claude/skills/gstack/ship/sections/review-army.md`. They are named by section rather than line number on purpose — line numbers drift on every `gstack-upgrade`. If a claim here stops matching gstack's behavior, grep those files for the section name.)

```bash
CHECKPOINT_SHA=$(git rev-parse HEAD)
STATUS="clean"        # or "issues_found" if any REAL BUG was triaged
FINDINGS='[{"fingerprint":"path/to/file.py:42:security","severity":"CRITICAL","action":"skipped"}]'
"$GSTACK_BIN/gstack-review-log" \
  "{\"skill\":\"fresh-review\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"status\":\"$STATUS\",\"commit\":\"$CHECKPOINT_SHA\",\"branch\":\"$BRANCH\",\"verdict\":\"$VERDICT\",\"findings\":$FINDINGS}"
```

Rules for the `findings` array:

- **Only buckets 2, 3, and 4** (REAL BUT BY DESIGN / STYLISTIC-NOISE / REVIEWER MISUNDERSTOOD), each as `action: "skipped"`. Those are the decisions worth carrying forward.
- **Never log a bucket 1 (REAL BUG) finding.** Omitting it is deliberate: ship re-reviews it, which is the regression check on your fix. Logging it as `skipped` would suppress the one finding you most need re-verified.
- `fingerprint` is exactly `path:line:category` — repo-relative path, the finding's line, the reviewer's category slug lowercased. A wrong fingerprint simply fails to match, and the finding resurfaces in ship. **This whole step fails safe in that direction**: the worst outcome is a review you already answered showing up again, never a real bug being hidden.
- `status` is `"clean"` only when bucket 1 is empty.

If `gstack-review-log` exits non-zero (malformed JSON, `bun` missing, no gstack install), continue — this is a convenience handoff, never a gate. Note it in the report.

Two things this does **not** do: it does not stop ship's pre-landing review from running, and it does not flip the Eng Review row on ship's readiness dashboard — that row only reads entries from skills named `review` or `plan-eng-review`, and Pass B's own `/review` entry is what satisfies it.

In no-checkpoint mode, still write the entry, but expect no suppression: the logged commit is the pre-existing HEAD, so every file you later commit reads as "changed since the review".

### Step 8: Restore working state

Regardless of verdict, undo the checkpoint and restore the original index split:

```bash
git reset --soft HEAD~1
git reset --quiet                                   # unstage everything
echo "$STAGED_BEFORE" | tr '|' '\n' | sed '/^$/d' | xargs -r git add --  # re-stage what was staged
git status --short
```

Skip entirely if Step 4 was skipped or fell back to no-checkpoint mode.

Then tell the user: "Working tree restored — staged/unstaged split is back as it was. Address the action items above, then commit when ready."

This must run even on abort or error. If the user interrupts mid-review, restoring the tree is the first thing you do on the next turn.

### Step 9: Persist the report

Write the final triage to `$REPORT_DIR/report-$(date +%Y%m%d-%H%M%S).md`: verdict, scope (`DIFF_CMD`, base SHA, risk class), the triage table, which passes ran — explicitly including whether Codex executed — and which were skipped with why, the isolation-audit result, and the paths to the raw reports in `$RAW_DIR`. Print `$RAW_DIR` to the user — it is a mktemp dir and will not be guessable later.

## Failure modes and recovery

- **Checkpoint commit fails** → no-checkpoint mode (Step 4), skip Step 8, document it.
- **A pass returns nothing / errors** → log it as a skipped pass in the report and continue. No single pass is blocking; a review missing one pass is still worth having, but the verdict must say which lens was absent.
- **Codex did not run** (`CODEX_NOT_RUN`) → continue, and state in the verdict that this review is Claude-only. Never substitute a Claude pass for it. If cross-model coverage matters for this change, the fix is `codex login` / `gstack-config set codex_reviews enabled`, then re-run.
- **Subagent tries to fix code** → discard any diff it produced (`git checkout --` the affected paths), keep only its findings, and note the violation.
- **User aborts midway** → Step 8 first, then report what was collected.
- **Forbidden read detected** → Step 6 handles it: note, downgrade confidence, optionally re-spawn.

## What this skill does NOT do

- **Open a literal fresh Claude Code session.** For maximum isolation before a major release, tell the user: "Subagent isolation is strong but not perfect. For strongest fresh eyes, run `git worktree add ../review-wt HEAD`, start Claude Code there, and run `{{LATTICE_REVIEW_CMD}}`, `{{GSTACK_REVIEW_CMD}}`, and `{{CSO_CMD}}` manually."
- **Auto-apply fixes.** The calling session applies fixes after triage. This skill only diagnoses.
- **Replace a full security audit.** `/cso --diff` covers the changed surface only. A full `/cso` (all phases, whole repo) is still a periodic job — this is the per-change gate.
- **Replace QA.** Nothing here proves the code runs. `/qa` still applies.
- **Run the CI gates.** Tests, coverage, and lint are `/ship`'s job. A `COMMIT` verdict says the code reads correctly, not that it passes.
- **Stop `/ship` from reviewing again.** Ship's pre-landing review is unconditional by design, and it reviews the *final* diff — post-fix, post-CHANGELOG, post-base-merge — which is a different artifact from what these passes saw. Step 7.5 makes that second pass quiet rather than absent: findings you already triaged away get suppressed, so ship raises only what is new.

## Examples

**"fresh review my changes before I commit"** → Steps 1–9; branch-scoped diff; three isolated passes (Codex riding inside Pass B); triage; tree restored; report in `$REPORT_DIR`. No questions asked at any point.

**"review this before I push"** with `auth/` in the diff → Step 3 classifies high-risk; `/cso` upgrades to `--diff --comprehensive`; Pass B is told "full structured review / P1 gate" so the structured Codex pass runs even on a small diff; four sources (lattice/gstack/codex/cso) triaged under the security floor.

**"/fresh-review"** on a branch with continuous checkpoint commits → `REVIEW_SCOPE="branch"` reviews every unshipped commit, not just the last one.
