# fresh-review — design notes

For maintainers. The skill never reads this file during a run. Each section gives the reasons for a rule that `skills/fresh-review/SKILL.md` or a file in `skills/fresh-review/references/` states in short.

## Why this skill exists

When you design, write, and review code in the same session, the reviewer-Claude already agrees with the design and knows the rationale. It rationalizes away its own decisions. Real review needs a reviewer that *lacks* the producer's context. This skill spawns subagents with strict context limits, optionally adds an out-of-process cross-model reviewer, and then triages their findings back in the producer context, where "by design" can be properly justified.

The same separation matters even more for *describing* a change. A summary written by someone who knows the intent restates the intent. A brief built from the code alone can contradict it. So Pass U, which sets the risk tier and draws the before and after, is isolated like the critics.

## Why a risk tier, and why only high stops

The user is an architect. They judge parts and how the parts connect, not lines of code, and Claude reads the code better than they do. So the human's time goes where the architecture moves, and nowhere else:

- **Low** (no architecture change) needs nothing from the human. The code review runs on its own, and the chat shows one line and the verdict.
- **Medium** (a change inside one bounded context) is worth seeing but rarely worth stopping for. The brief prints and the code review runs in the same turn. The architect reads it and can still stop the run.
- **High** (a change across a boundary, or one that is hard to undo) is where an architecture mistake costs the most, and where reviewing code the architect wants rebuilt wastes the run. So the run stops for a go. A rejected design ends the run with no code review.

An earlier version (0.13–0.20) explained every change and quizzed the user with open questions before any review. It cost a round trip on every run, including the many runs with no architecture change, and it tested whether the user had read the explanation rather than whether the design was right. The tier replaces it.

The tier is separate from the mechanical `RISK`. `RISK` counts risky patterns and sets the code review's depth (`/cso --comprehensive`, a required Codex); the tier is about architecture and sets what the human sees. A one-line change to an auth check has no architecture change and a deep review. A high tier also requires Codex: a boundary change is where a second model family pays.

## Why the diagrams use domain words only

A diagram with class names is a code diagram, and the architect does not read code. Bounded contexts, aggregates, services, events, stores, and outside systems are the level at which the architect decides. The same node ids in both diagrams let the eye find what moved. When the repo has no DDD document (`VOCAB: atom-defaults`), the context names are inferred from the code, and the brief says so.

## Why chat has no code

The findings are for the session that fixes them, and that session reads `report.md`. The architect needs to know what goes wrong, for whom, and when — one plain sentence each. The diffs stay one link away.

## Why the verdict words change on someone else's PR

The verdict vocabulary is not cosmetic. `COMMIT` on someone else's PR reads as an instruction to the wrong person about the wrong tree, and this skill's output is designed to be read verdict-first.

## Why gstack's `/review` is not a default pass

`/review` is the exact skill `/ship` runs at its own Step 9 — unconditionally, on the final diff. On your own branch, running it here too pays for the same specialists, Red Team, and adversarial subagent twice, and ship's Step 9 re-dispatches on every fix cycle. So on your own branch it never runs here.

Reviewing someone else's PR, no ship of yours will run it. It is still opt-in there (`--army`), because the logs show it costs more than every other pass together: a median 15 minutes and about 30% of the run's tokens, spread over a lead agent and four or more specialist agents. Pass I covers correctness, performance, and contract breaks in one direct read. `--army` adds the full specialist set when a PR needs it.

| | fresh-review (this skill) | `/ship` Step 9 / Step 11 |
|---|---|---|
| Architecture tier and brief | Pass U (stops on high) | — |
| Correctness, performance, contracts | Pass I | specialists |
| Standards conformance | Pass A (lattice) — only with a lattice context | `testing` / `maintainability` |
| Security | Pass B (`/cso`, confidence-gated) | `security` specialist (ungated) |
| Cross-model review | Pass C (`codex review`) — when requested, and always on `RISK: high` | Codex structured + adversarial |
| Full specialist army, Red Team | pr-remote with `--army` only | owned here |

The reverse redundancy — ship re-running what *this* skill already did — is handled from the ship side by `references/ship-dispatch-gate.md`.

## Plugin root candidates (Step 0)

Candidates are ordered most-authoritative first: an ambient value wins; then the Skill tool's own base directory (two levels up from `skills/fresh-review`); then this repo's own checkout (the dev / worktree case, so local edits are what runs); then the marketplace clone; then the highest-versioned entry in the version-keyed cache. The first directory that actually holds `scripts/fr-preflight.sh` wins, so a stale or partial candidate is skipped rather than trusted.

## Preflight (Step 1)

**Neither of the last two can fire under `--pr`,** and that is deliberate: both describe the *local* tree, which is not the subject of a pr-remote review. A clean checkout on `main` is the normal state to review someone else's PR from, and `nothing_to_review` there would stop the run with a message that reads exactly like a correct answer. A conflicted index is likewise harmless in that mode — it is never staged, committed, or restored.

`AHEAD` counts commits **not in the base branch** (`$DIFF_BASE..HEAD`) — deliberately not `@{upstream}..HEAD`. Comparing a branch against its own upstream asks the wrong question: a fully pushed PR branch reports `AHEAD=0` even though its PR diff is a hundred commits wide, and a branch with no upstream falls back to `0`. Either would stop the skill with "nothing to review" while a complete, reviewable diff sits in front of it. The `@{upstream}` form survives only as the degraded fallback for when there is no `origin/$BASE` to merge-base against.

The run directory persists, unlike a `mktemp` scratch dir — it is the record that makes a run analyzable afterward. It lives under `.fresh-review/` when that path is already gitignored, and under the git dir otherwise. The script never appends to `.gitignore`: mutating a tracked file mid-review would inject a change into the diff under review.

`LOG_DIR` is deliberately the **common** git dir, not the per-worktree one. In a worktree `git rev-parse --git-dir` resolves to `.git/worktrees/<name>`, so an index written there would fragment across worktrees and be deleted with them — and cross-run analysis would silently see only a fraction of the history. Run directories stay local and disposable; the index in `LOG_DIR` is the durable record. Entries may therefore outlive the run directory they point at, which is expected.

## Why the skill never runs the app (Step 4.6)

Earlier drafts launched the app to screenshot the changed routes. That was removed in v0.9.0 because launching a review tree is an arbitrary-code-execution risk on the reviewer's host, and the risk cannot be gated away:

- A tree under review may hold untrusted code — a PR fetched with `--pr` (pr-remote), **or** a fork / dependabot branch checked out locally and reviewed with `--mode pr`.
- Launching it (`preview_start` on a committed `.claude/launch.json`, or a `dev`/`storybook` script) runs the author's code with the reviewer's live `gh` / cloud / DB credentials.
- **Provenance — "is this tree my own code?" — is not mechanically decidable.** A locally-checked-out untrusted branch is `REVIEW_SCOPE=branch` with `SOURCE_ROOT` pointing at your own checkout, indistinguishable from your own feature branch. Gating on scope or filesystem location (the earlier fix attempt) leaves the local-checkout door open, and git author metadata is spoofable. There is no signal here worth trusting with code execution.

So the skill does not launch, in any mode. Do not reintroduce a launch path gated on scope, worktree disposability, or author metadata — none of those is a trust boundary.

From 0.21.0 the brief shows the screenshots the PR description already carries (`fr-ui-images.sh`). That needs no code to run. The script fetches only from GitHub's attachment hosts, sends the `gh` token only there (curl drops it on the redirect to the storage host), caps the count and the size, and keeps a file only when its magic bytes say it is an image. A link to any other host is counted and left alone: fetching it would tell that host the user opened the PR.

## Why each pass carries an explicit stop list (Step 5)

Each of these commands is a full interactive workflow that ends in *acting*, not merely reporting: `/cso` ends in a remediation conversation, `/lattice:review` ends by writing to a tracked file, and `/review` (Pass R) is fix-first — its Step 5 auto-applies mechanical fixes to the tree before it ever asks. A generic "be non-interactive and read-only" in the isolation contract does not reliably beat a nested skill's own numbered steps — the subagent is reading that skill as executable instructions, and the last instruction it reads wins. So each pass below names the specific sub-steps to skip, *by their heading*, and Step 6.5 verifies the outcome mechanically rather than trusting the prompt. Both are needed: the prompt sets intent, the check catches the miss.

Two clarifications on the non-interactive lever, since it is easy to reach for the wrong one:

- `SPAWNED_SESSION: true` is the mode we want. gstack's own spawned-session block ("Skill routing" in `~/.claude/skills/cso/SKILL.md`) tells the skill to auto-choose the recommended option instead of calling AskUserQuestion.
- **Do not set `GSTACK_HEADLESS`.** It classifies the session as `headless`, and gstack's AskUserQuestion-failure fallback maps `headless` to `BLOCKED — stop and wait` (`~/.claude/skills/gstack/bin/gstack-session-kind`). That is the opposite of unattended: it would hang the pass on the first question rather than defaulting past it.

## Codex invocation choices (Pass C)

Four things about this invocation are deliberate:

- **`codex review`, not `codex exec`.** `review` scopes natively and emits structured, severity-marked findings that drop into the triage table. `exec` returns prose that would have to be parsed. gstack uses `exec` for its adversarial pass and gates `review` at 200+ lines as its own cost control; that gating does not bind us once Codex is off the critical path.
- **Scope built from `REVIEW_SCOPE`, and therefore no custom prompt.** The CLI rejects `[PROMPT]` together with `--base` (`error: the argument '[PROMPT]' cannot be used with '--base <BRANCH>'`), so the isolation contract cannot be injected. `--base` still wins: a separate process running a different model family with no conversation history is the strongest isolation of any pass here, and handing it the base avoids spending agentic turns rediscovering the diff. The `case` above picks the scope flag per mode, and getting it wrong silently reviews the wrong commit range: `branch` diffs against the base branch (`--base "$BASE"`); `working` has no branch to diff and uses `--commit "$CHECKPOINT_SHA"`; `pr` must use `--base "$DIFF_BASE"` (the merge-base SHA, not `$BASE`) because a branch *name* there resolves against local refs and would silently diff the PR head against your own `main`.
- **`cd "$SOURCE_ROOT"`.** In review mode this is the repo root and the `cd` is a no-op. In pr-remote it is the only thing pointing Codex at the PR's commit instead of your checkout.
- **`approval_policy="never"` and `sandbox_mode="read-only"`.** A non-interactive background run that stalls on an approval prompt is indistinguishable from a slow one. Read-only also enforces "do not fix anything" at the process level rather than by instruction.
- **No `--enable web_search_cached`.** gstack enables it; for a diff review it rarely pays and it adds latency.

Budget expectations: measured floor is ~30s on an *empty* diff (process start, git probe, one model round trip). Real diffs run minutes. That floor is why Codex must never gate the verdict.

## Ship handoff internals (Step 8.6)

This entry does two things downstream. Ship's **"Cross-review finding dedup"** step suppresses any finding whose fingerprint was logged with `action: "skipped"` on this branch, provided that file has not changed since the logged commit — that is findings-level, and it is consumed at ship's Step 9.3, *after* every specialist has already run. The dispatch-level saving is separate and comes from `references/ship-dispatch-gate.md`, which reads this same entry *before* Step 9 fans out.

(Ship's behaviors live in the external gstack install: `~/.claude/skills/ship/SKILL.md` and `~/.claude/skills/gstack/ship/sections/review-army.md`. Named by section rather than line number because line numbers drift on every `gstack-upgrade`.)

**What this does not do:** it does not flip the Eng Review row on ship's readiness dashboard. That row only reads entries from skills named `review` or `plan-eng-review`, and this skill logs as `fresh-review`. Ship will print "No prior eng review found — ship will run its own pre-landing review in Step 9" every time. That is correct and must not be routed around: the row tracks eng review of the **final** diff, which this skill deliberately does not review.

## Index restore (Step 9)

The index restore is gated on those two states **by name**, not on `≠ skipped`, and the difference only shows up in pr-remote mode: nothing was ever staged there, so a `read-tree` would restore an index snapshot the user never asked for and silently discard anything they staged while the review was running. That is a data-losing no-op with no output to notice it by — `INDEX: restored` looks exactly like success.

## What the run log is for (Step 10)

**What this log is for.** Three questions it is designed to answer across runs:

- *Where does the time actually go?* Per-pass `duration_s` replaces the impression that "the run is slow" with the name of the pass that is slow.
- *Is Codex earning its place?* Now that Codex is opt-in, the question is two-sided: `codex_requested` across runs shows how often anyone reaches for it, and `codex.duration_s` against `codex.changed_verdict` over the runs that did request it is the evidence for whether it pays off when they do.
- *Which pass produces noise?* A pass whose findings land overwhelmingly in buckets 3 and 4 is miscalibrated for this repo and should be re-scoped or dropped.
- *Is the brief worth its stop?* `architecture.tier` across runs shows how often a change moves the architecture; a repo where nearly every change is `high` has a Pass U that has stopped discriminating. `architecture.gate: rejected` counts the designs the architect stopped before the code review. The `architecture` pass's `title_mismatch` says whether PR titles in this repo can be trusted.
- *Did the blocker bar stop the loops?* `triage.real_bug` per run, and how many re-reviews a PR needs, against the schema-12 runs (about seven blockers per run).

## Run-log schema history

**Schema history.** `schema:14` (plugin 0.21.0) replaces the understanding gate with the risk tier: `architecture` now holds `tier` (`low`/`medium`/`high`/`unknown`), `gate` (`auto`, `shown`, `approved`, `carried`, `pending`, `rejected`, `failed`), `parts`, `diagram` (`before,after` or `none`), and `ui_images`; `decisions`, `questions`, and `rounds` are gone. The `understanding` pass is renamed `architecture`. The `risk` pass (Pass K) and the top-level `risk_level` are gone — the tier takes their place — and `ui_preview` becomes `ui` (`frontend`, `images`, `links_skipped`). `codex_reason` adds `tier` and drops `risk-pass`. Reading a `schema:13` entry, treat `architecture.gate` `approved`/`carried`/`skipped` as an approval and `risk_level` as an approximation of the tier. Within `schema:13`, from plugin 0.19.0, `architecture.diagram` is a comma-separated list of the diagrams shown (`class`, `sequence`, `flow`) — Pass U now also draws a flow diagram; read an earlier `both` as `class,sequence`. From plugin 0.16.0, `architecture.diagram` can be `both` — Pass U now draws a class and a sequence diagram; earlier `schema:13` entries hold one kind at most. `schema:13` replaces the architecture gate with the understanding gate (the `architecture` object keeps its name and adds `questions` and `rounds`; new gate values `waived` and `trivial`; `rejected` and `not_needed` are gone), drops the `narrative` and `eng-review` passes (their jobs moved to the `understanding` pass), adds the `implementation` pass, makes `lattice` conditional on the new top-level `lattice_context` and `review` conditional on `army_requested`, and adds `comments` and `triage.should_fix` (bucket 5). Reading a `schema:12` entry, treat `lattice_context` and `army_requested` as true — both passes always ran then — and `should_fix` as 0. `schema:12` adds `plugin_version` (the version of the plugin copy that ran, which can lag the installed one in a desktop session), `delta.source` (`record` or `runs_index`: where the last review was found), the `carried` architecture gate, and three delta reasons, `prior_blockers_unknown` and — after the user chose the whole PR — `no_prior_review` and `prior_reduced_coverage` as a chosen full review. Reading a `schema:11` entry, treat `plugin_version` and `delta.source` as absent-unknown (the source was always the record), and read its `full` reasons as automatic. `schema:11` adds re-review: an optional `delta` object (present only when `--delta` was asked for) and an optional `fix-check` pass (Pass F). On a `schema:11` entry with `delta.applied:true`, `diff`, `triage`, and the findings cover only the changes since `delta.prior_head`. Reading a `schema:10` entry, treat `delta` as absent — every review covered the whole PR. `schema:10` adds stack mode: an orchestrator entry with `mode: "stack"`, `verdict: "HANDOFF"`, no passes, and a `stack` object holding the plan; and an optional `stack` object on each unit's review entry linking it back by `id`. Reading a `schema:9` entry, treat `stack` as absent — stack mode did not exist. `schema:9` adds `codex_reason` (why Codex ran: the user asked, or high risk forced it — a `schema:8` `codex_requested:true` always means the user asked) and an `architecture` object (the gate's outcome, decision count, and whether a diagram was shown) and two optional passes, `architecture` (Pass D) and `eng-review` (Pass E). A run whose gate did not clear has neither the critic passes nor a normal verdict. Reading a `schema:8` entry, treat `architecture` as absent-unknown — the gate did not exist, and the implementation passes always ran. `schema:8` adds a `pr_context` object (whether the PR's description/discussion was gathered for triage, and its counts) and, for repos whose PR gate runs a static-analysis tool, a `static_analysis` object plus an optional `static-analysis` pass (Pass W) — present in any mode when the PR carried analyzer findings, absent otherwise. Reading a `schema:7` entry, treat `pr_context`, `static_analysis`, and the `static-analysis` pass as absent-unknown — none existed, and chat then carried the full narrative sections and coverage notes that `schema:8` moves to `report.md`. `schema:7` adds an optional `risk` pass (pr mode only), a top-level `risk_level` (Pass K's `low`/`med`/`high`, distinct from the always-present mechanical `risk`), a `ui_preview` object (pr mode only), and a `narrative.diagram` field. Reading a `schema:6` entry, treat `risk_level`, `ui_preview`, the `risk` pass, and `narrative.diagram` as absent-unknown — none existed, and the narrative then carried prose sections rather than a diagram. `schema:6` adds an optional `review` pass — present only on pr-remote runs where `HAS_GSTACK: 1`, carrying Pass R's findings from gstack `/review`. Do not confuse it with the `schema:2` `gstack` pass: both come from running `/review`, but the old one ran in *every* mode and this one is pr-remote only. Reading a `schema:5` entry, treat the `review` pass as absent-unknown — it did not exist, and pr-remote then covered nothing structural. `schema:5` adds `codex_requested` and makes the `codex` pass optional — absent when the run did not request Codex. Reading a `schema:4` entry, treat `codex_requested` as absent-unknown but assume `true`, since Codex ran unconditionally then and its pass will be present. `schema:4` adds `mode`, an optional `pr` object, and an optional fourth `narrative` pass. `schema:3` has three passes and no mode field — read its absence as `review`, since pr mode did not exist. `schema:2` entries carry a different fourth pass, `gstack`, from when this skill ran `/review` itself; a tool reading across versions must not treat either fourth pass's absence as a failure, and must not confuse the two — `gstack` reported findings, `narrative` never does. The shape is otherwise deliberately generic — `skill`, `run_id`, `duration_s`, `passes[]`, `verdict` — so a future cross-skill run-analysis tool can read it alongside other skills' logs without a per-skill parser.
