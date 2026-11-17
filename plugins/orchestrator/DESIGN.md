# orchestrator — design notes

For maintainers. The skill never reads this file during a run. Each section gives the reasons for a rule that `skills/orchestrator/SKILL.md` or `skills/orchestrator/references/contracts.md` states in short.

## Why this skill exists

Shaked runs one ticket through the development pipeline by keeping a parent session open and starting one child session per stage. Until now the parent's behavior lived only in chat prompts and in memory notes. The insights report (2026-07-22 to 2026-11-16) and the orchestrator transcripts show the same failures again and again:

- A child ends a turn while it still waits for a test run, a review pass, or CI, and the parent reads the turn note as "done".
- A child returns a short verdict with no findings, or a design that is still `draft`.
- The parent only relays a note and does not advance. Shaked asks "status?" or "Why you are not orchestrating?".
- Expired AWS SSO and permission denials stop a child, and nobody tells Shaked the exact fix.

This skill makes the parent's job explicit: start each stage, check each child's final report against a written contract, nudge once, and stop and ask when the contract still fails.

## Sources

The stage list is not invented. It comes from:

- `~/activate/vi-activate/docs/pipeline.md`, the team's single source of truth for the phases.
- About 15 orchestrator sessions in `~/.claude/projects/-Users-shaked-eyal-activate-vi-hub--claude-worktrees-*` (for example `dev-pipeline-triage-37c8df` session `eedb1794`, `dev-pipeline-starting-point-d0997a` session `4c189582`, `review-pr-5926-1faf1e` session `3ca07f74`), with 172 `start_session` calls in total.
- The memory notes in `~/.claude/projects/-Users-shaked-eyal-activate-vi-hub/memory/` named `orchestrator-*` and `handoffs-*`.

The handoff pointed at `~/.claude/projects/-Users-shaked-eyal-activate/`. That folder has no pipeline runs; its matches were skill listings.

## The stages

| # | Stage | Who runs it | Child command |
|---|---|---|---|
| 0 | TRIAGE | the parent | — (reads the ticket and `pipeline.md`) |
| 2 | SPEC | child | `/lattice:requirement-forge` |
| 3 | DESIGN | child | `/lattice:design-blueprint`, then the plan reviews the surface needs |
| 4 | BUILD | child | `/lattice:code-forge` (bug: `/lattice:bug-fix`, refactor: `/lattice:refactor-safely`) |
| 5 | REVIEW | child | `/fresh-review:review` (`--codex` for auth, IaC, migration, cross-account) |
| 6 | QA | child | `/qa` |
| 7 | HARVEST | child | harvest learnings and prune the requirements index |
| 8 | SHIP | child | `/ship` |

Phase 1 (SHAPE) is optional and rare, so the skill starts it only when Shaked asks. Phase 9 (post-ship: `/monitor-pr`, `/canary`) is out of scope: the ship child turns on Auto-fix, and the app wakes it.

Triage picks a track, as `pipeline.md` Phase 0 says. A bug or refactor skips SPEC and DESIGN and rejoins at REVIEW. Trivial, docs, or config work takes the fast track. QA is skipped for libraries and docs.

## Why triage stays in the parent

Triage is a routing decision, not a work product. In every transcript the parent did it. It needs the ticket, `pipeline.md`, and the closed check, and nothing else. A child for it would cost a session and a round trip to pick one word.

## Why a completion contract

A child's turn note is not proof of done. The app says so itself: "A note on a session's turn does not mean its task is done." The contract turns "done" into a short list of facts the parent can check. Each child ends its final turn with a `STAGE REPORT` block in a fixed shape. The shape is what makes the check mechanical.

The block has a `status` line: `done`, `waiting`, or `blocked`.

- `waiting` means the child is waiting for something that will wake it (a test run, a pass, CI). The parent does not check the contract and does not nudge. It reports and waits for the next note.
- `blocked` means only Shaked can unblock it (SSO, a permission, a decision). The parent tells Shaked the exact step.
- `done` is the only status the parent checks against the contract.

This split answers the most common failure in the transcripts: a parent that nudged a child that was only waiting, or trusted a child that was not done.

## Why a script checks the block

`scripts/orc-check.sh` reads a child's report and prints `CONTRACT: met` or `CONTRACT: unmet` with the missing items. It is justified because every check in it is mechanical:

- the block is present and has the stage's required fields;
- the review verdict word is one of a fixed set;
- the paths it names exist;
- the commit SHA it names resolves in the repo;
- the design document's status line says `approved`.

Whether the tests are good, or the findings are right, is not mechanical. The script does not try. Those stay with Shaked and with the review stage.

## Why one nudge, then stop

The first miss is usually a child that stopped early. One message that names the missing items fixes most of them. A second miss means something is wrong that a third message will not fix: a broken tool, a wrong scope, an unclear ticket. Looping there burns tokens and hides the problem. So the parent stops and reports to Shaked with the two reports and the missing items.

The nudge goes to the **same** child with `SendMessage`, not to a new session:

- The child keeps its context and its partial work. A fresh session would redo it.
- The app refuses `start_session` on a turn that a session note or another automated event started ("Start sessions only on the user's own words to you here"). A contract check almost always runs on such a turn. A restart there would fail.

A new session is used only when the child is gone (archived, errored, or not reachable by id), and only on Shaked's own turn.

The attempt count lives in a small state file, so it survives a context compaction. Without it the parent could forget it already nudged and loop.

## Why the parent does not start the next stage on its own

The app allows `start_session` only on Shaked's own words. So when a stage passes its contract on an automated turn, the parent proposes the next stage as a card and says one line: what passed, and "say go to start <stage>". When Shaked's own message already asked for the next stage (for example "run it through build"), the parent starts it in that turn.

This keeps the rule from the memory note `orchestrator-acts-on-every-session-note`: never only relay. Always verify, then advance or ask for the one go.

## Why every status is a table

Shaked asked for every status in table form. With several stages and PRs in flight, prose hides what is done and what waits on him. The memory notes say the same: `orchestrator-reports-include-pr-table` and `orchestrator-status-on-every-session-message`.

Every message the parent sends Shaked, on every note, event, or question, ends with:

1. **The stage table.** One row per stage of the ticket's track.

   | Stage | Session | Status | Contract | Needs you |
   |---|---|---|---|---|
   | SPEC | [w1-10-spec](#local_…) | done | met | — |
   | DESIGN | [w1-10-design](#local_…) | blocked | — | approve design doc |
   | BUILD | — | not started | — | — |

   `Status` is `not started`, `running`, `waiting`, `blocked`, `done`, `skipped`, or `stopped`. `Contract` is `met`, `unmet (nudged)`, `unmet (stopped)`, or `—`.
2. **The PR table**, when the ticket has a PR: one row per PR, with what it is, review state, CI, and whether it can merge now. The parent reads it fresh with one `gh` call per message and never copies an older table.
3. **A `Needs you:` line** with every action waiting on Shaked, or `nothing`.

Above the tables there are at most two short lines of prose. A message is never only "nothing new".

## Gates that never move

These wait for Shaked's explicit words. The skill never batches them, skips them, or answers them for him:

- SPEC approval and DESIGN approval (`status: approved` in the context doc).
- A high-risk architecture stop in REVIEW. On a branch review fresh-review asks "say go"; in a stack unit the verdict is `ARCH-PENDING`. Both are `blocked`, not failures.
- Which review findings to fix.
- Each harvested learning bullet.
- Push, opening a PR, marking it ready, merging.
- Posting a review to GitHub (only on "post it", via `/post-review`), and any post to Slack, Confluence, or a PR.

## Why fresh-review stack mode is untouched

Shaked reviewed stack mode and chose no change. A stack review still runs as manual handoffs, and the units report back as pasted `STACK REPORT` lines. The REVIEW contract only reads that line when the child is a stack unit. It does not start the units.

## Why two verdict vocabularies

The pipeline reviews the child's own branch, so fresh-review says `COMMIT`, `COMMIT-WITH-FIXES`, or `DO-NOT-COMMIT`. A PR review or a stack unit says `APPROVE`, `APPROVE-WITH-COMMENTS`, or `REQUEST-CHANGES`, and a stack unit can say `ARCH-PENDING`. The contract accepts both sets and maps them the same way.

## Preflight

The SessionStart hook `~/.claude/hooks/preflight.sh` already checks AWS SSO. The skill checks only what a run needs and the hook does not cover: the Asana MCP (ticket and closed check), `gh auth status`, and the session tools. If a child later reports an SSO error, the parent stops that stage and gives Shaked the exact command from the error, usually `aws sso login --sso-session vi-sso`.

A ticket that is closed (Asana task `completed`, or its PR merged) is skipped with one line.

## Research framing

When Shaked frames the ask as research or investigation, every child is read-only on repos, and the parent does not propose BUILD, REVIEW fixes, or SHIP.

## Model

Every child starts with `model: "sonnet"` unless Shaked names another model.

## Files

| File | Why it exists |
|---|---|
| `skills/orchestrator/SKILL.md` | the parent's workflow |
| `skills/orchestrator/references/contracts.md` | the per-stage contracts, kept apart so Shaked can edit them |
| `skills/orchestrator/references/child-brief.md` | the brief template every child gets, with the `STAGE REPORT` shape and the reporting rule |
| `commands/orchestrate.md` | the desktop app runs commands, not plugin skills |
| `scripts/orc-check.sh` | the mechanical contract check |
| `scripts/orc-state.sh` | the attempt count and stage state, so they survive compaction |
| `tests/test-check.sh`, `tests/test-state.sh` | one suite per script |

No new dependency. The scripts need `bash`, `git`, and `python3`, which the repo's other scripts already use.
