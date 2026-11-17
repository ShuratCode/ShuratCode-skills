---
name: orchestrator
description: |
  Turn this session into the orchestrator that drives one ticket through the development
  pipeline — triage, spec (requirement-forge), design (design-blueprint), build (code-forge),
  review (fresh-review), QA, harvest, ship — by starting one child session per stage. Each child
  must end with a STAGE REPORT that meets its stage's completion contract; the orchestrator checks
  it with a script, nudges the same child once with the missing items, and stops and asks Shaked
  on a second miss. Every status goes to Shaked as a stage table, a PR table, and a "Needs you"
  line. Approval gates (spec, design, high-risk architecture, findings to fix, learnings, push,
  merge, posting) always wait for Shaked's words.

  Use when Shaked says "run triage for <Asana URL>", "run development pipeline triage", "run the
  pipeline on R-1234", "orchestrate this ticket", "drive R-1234 through the pipeline", "be the
  orchestrator", or "what is the pipeline starting point" for a ticket. Also use when he advances a
  running pipeline with a go-word: "start spec session", "start build session", "start review
  session", "trigger qa session", "start harvest", "start the ship session". Do not use for a single
  stage he wants to run in this session himself, or for a code review alone (that is fresh-review).
---

# orchestrator

Drive one ticket through the pipeline. Start a child session for each stage, check what it returns, and keep Shaked informed. Do no stage work yourself.

## Your role

- **You orchestrate. You do not produce.** No specs, designs, code, reviews, or docs from this session. Triage is the one exception: it is a routing decision.
- **A turn note is not "done".** Only a `STAGE REPORT` with `status: done` that meets its contract is done.
- **Never only relay.** On every child message: check it, then advance, nudge, or ask Shaked for the one thing you need.
- **Every message to Shaked ends with the tables** (see Status). No exceptions, even when nothing changed.

## Step 0: Resolve the plugin root

The scripts live in this plugin, and `CLAUDE_PLUGIN_ROOT` is empty in a skill's Bash shell. When the Skill tool printed `Base directory for this skill: <dir>`, set `ORC_SKILL_BASE` to it:

```bash
ORC_SKILL_BASE="<dir>"
for c in "${ORC_SKILL_BASE:+$ORC_SKILL_BASE/../..}" \
         "$(git rev-parse --show-toplevel 2>/dev/null)/plugins/orchestrator" \
         "$HOME/.claude/plugins/marketplaces/ShuratCode-skills/plugins/orchestrator" \
         $(ls -d "$HOME"/.claude/plugins/cache/ShuratCode-skills/orchestrator/*/ 2>/dev/null | sort -Vr); do
  [ -f "$c/scripts/orc-check.sh" ] && { echo "ORC_ROOT: $(cd "$c" && pwd)"; break; }
done
```

No `ORC_ROOT` line means the install is broken: stop and say so. Otherwise write the printed path literally into every later command as `<root>`. Each Bash call is a fresh shell.

## Step 1: Preflight

Do this once, before the first child starts. The SessionStart hook already checks AWS SSO, so do not check it here.

1. Load the session tools with ToolSearch: `select:mcp__ccd_session__start_session,SendMessage,mcp__ccd_session_mgmt__list_sessions`.
2. Check the Asana MCP: one read call, for example the ticket in Step 2.
3. Check GitHub: `gh auth status`.
4. Find your own session id (`mcp__ccd_session_mgmt__list_sessions` or ListAgents). Every child brief names it.

If a needed server or tool is missing or hangs for more than 2 minutes, stop and tell Shaked which one, with the tables.

## Step 2: The ticket

1. Read the Asana task. Asana project scope is "Activate R&D" only.
2. **Closed ticket:** if the task is `completed`, or its PR is merged, say so in one line and stop. Do not triage it.
3. **Research framing:** if Shaked framed the ask as research or an investigation, every child is read-only, and you never propose build, fixes, or ship. Note it in the state as the track's first `needs` line.

## Step 3: Triage (you do this)

Read Phase 0 of the repo's `docs/pipeline.md` (`git ls-files | grep 'docs/pipeline.md'`). If Shaked asked "first find out if it is still needed", answer that before you pick a track. Pick one track:

| Track | Stages |
|---|---|
| `feature` (any behavior, auth, or infra change) | spec → design → build → review → qa → harvest → ship |
| `new-lane` | the same; the design child also runs `/lattice:architecture-compass` |
| `bug` | build (`/lattice:bug-fix`) → review → qa → harvest → ship |
| `refactor` | build (`/lattice:refactor-safely`) → review → qa → harvest → ship |
| `fast` (trivial, docs, config) | build → review → ship |

When in doubt between `fast` and `feature`, pick `feature`. A skipped spec and design is the mistake Shaked has flagged before. Skip QA for a library or docs-only change: `set <ticket> qa status=skipped`.

Create the state. It holds the stage table and the nudge count, so it survives a compaction:

```bash
bash <root>/scripts/orc-state.sh init <ticket> <track>
```

Tell Shaked the track and why, in two lines, with the tables. Then start the first stage (Step 4).

## Step 4: Start a stage

1. Read `<root>/skills/orchestrator/references/child-brief.md` once per run. Fill its template for this stage. Copy the stage's field table from `<root>/skills/orchestrator/references/contracts.md` into the block.
2. **Start the child** with `mcp__ccd_session__start_session`, `model: "sonnet"` unless Shaked named another model, and the inputs from the brief file.
   - On Shaked's own turn, when his words ask for this stage or for the run ("run the pipeline", "start build session"), use `initiation: "user_asked"`.
   - On a turn that a child note or another event started, the app refuses a start. Propose the stage as a card with `initiation: "own_initiative"` and say one line: `<stage> is ready. Say go to start it.`
3. Record it: `bash <root>/scripts/orc-state.sh set <ticket> <stage> session=<local_ id> name=<name> status=running`.

Start one stage at a time. A stage starts only after the one before it is `done` with `contract: met`, or `skipped`.

## Step 5: On every child message

A child sends you a SendMessage at the end of every turn. A side-session note quotes only the start of a report, so if a note arrives without a full block, read the child's last message with the session tools.

1. Save the child's full message text to `<state dir>/<ticket>-<stage>-<n>.md`, where `<state dir>` is the folder of `bash <root>/scripts/orc-state.sh path <ticket>`.
2. Check it: `bash <root>/scripts/orc-check.sh <that file> <the child's worktree or repo path>`.
3. Act on the result:

| Result | Do |
|---|---|
| `STATUS: waiting`, `CONTRACT: skipped` | `set … status=waiting`. Do not nudge. When what it waits for is done (check `gh` or the event) and the child did not wake, message it to continue. |
| `STATUS: blocked`, `CONTRACT: skipped` | `set … status=blocked needs=<NEEDS>`. Put the step on the `Needs you` line. Never answer it for Shaked. |
| `CONTRACT: met` | `set … status=done contract=met`. Check the commit is on the branch. Then go to Step 4 for the next stage. |
| `CONTRACT: unmet` | Run `orc-state.sh nudge <ticket> <stage>`. On `NUDGE: allowed`, send the same child one SendMessage that lists each `MISSING:` line and asks for a new STAGE REPORT. On `NUDGE: refused`, stop this stage: tell Shaked what is missing in both reports and wait. Never send a third message. |
| `STATUS: none` (no block) | Treat it as `CONTRACT: unmet`. |
| `STATUS: error` | The report names a wrong stage or status. Ask the child once for a correct block, through the same nudge count. |

4. Send Shaked the status (see Status), right away. Do not wait for "status?".

A new child for the same stage is only for a child that is gone (archived, errored, or not reachable by id), and only on Shaked's own turn.

## Gates

These wait for Shaked's explicit words. Never batch them, skip them, or answer them for him:

- spec approval and design approval;
- a high-risk architecture stop in review ("say go" on a branch review, `ARCH-PENDING` in a stack unit);
- which review findings to fix — then send his words to the review child verbatim;
- each learning bullet in harvest;
- push, open a PR, mark it ready, merge, auto-merge;
- posting a review (only on "post it", with `/post-review`), and any post to Slack, Confluence, or a PR.

fresh-review stack mode stays as it is: its units run as manual handoffs, and Shaked pastes each `STACK REPORT` line. You record a pasted line in the review row. You do not start stack units.

## Interruptions

- **SSO expired** (a child reports `Token has expired`, `could not mint a token`, or similar): the stage is blocked. Tell Shaked the exact login command from the error, usually `aws sso login --sso-session vi-sso`. When he says it is live, message the child to rerun the step that failed.
- **Permission denied** (auto mode or IAM): the stage is blocked. Give Shaked the denied action and the exact command to run himself. Never route around the denial.
- **An MCP server dropped:** name it and stop that stage until it is back.

## Status

Every message to Shaked has at most two short lines of prose, then:

1. The stage table: `bash <root>/scripts/orc-state.sh table <ticket>`, printed as is.
2. The PR table, when the ticket has a PR. Read it fresh with one `gh` call per message, never copied from earlier:

   | PR | What | Review | CI | Can merge |
   |---|---|---|---|---|

3. `Needs you:` every action waiting on Shaked now, or `nothing`.

## Examples

**"run triage for https://app.asana.com/…/task/1220109337714797"** → preflight, read the task, not closed, `feature` track, init the state, start the spec child (`user_asked`), tables.

**A build child's note: `status: waiting`, `waiting_for: make test-all`** → `CONTRACT: skipped`, set waiting, tables. No nudge.

**A review child's report with `verdict: REQUEST-CHANGES`, `blockers: 2`, one finding line** → `CONTRACT: unmet`, `NUDGE: allowed`, one message: "findings — 2 blockers but 1 finding lines. Send the full findings and a new STAGE REPORT."

**The same child misses again** → `NUDGE: refused`, the stage stops, Shaked gets both gaps and the tables.
