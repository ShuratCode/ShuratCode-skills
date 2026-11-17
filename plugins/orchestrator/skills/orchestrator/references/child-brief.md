# Child brief

The parent fills this template for every stage and passes it as the `prompt` of `start_session`. Replace each `<…>`. Keep the stage line first, so the child runs the skill at once.

## Template

```
<stage line, from the table below>

Ticket: <ticket id> — <ticket title>. Asana: <task URL>.
Branch: <branch>. Track: <feature | bug | refactor | fast | new-lane>.
Inputs: <paths and SHAs from earlier stages; a design the parent sketched goes here marked "not approved">.

Rules:
- Stay in this stage. Do not start the next stage.
- Commit this stage's output on the branch. Do not push, open a PR, or merge without Shaked's OK.
- Never post to GitHub, Slack, Confluence, or a PR without Shaked's explicit words.
- <research framing only:> This is research. Read-only on every repo. No code changes.
- If AWS fails with an SSO or token error, stop and report status: blocked with the exact login command from the error.
- If a permission is denied, stop and report status: blocked with the denied action and the exact command Shaked can run.

Done: <the stage's done line, from the table below>.

Reporting — required:
At the end of EVERY turn, send the orchestrator one SendMessage to <parent local_ id>. Its text ends with a STAGE REPORT block. A turn that ends while you wait for tests, a pass, CI, or a reply is status: waiting, with waiting_for. A turn that needs Shaked is status: blocked, with needs. Only the last turn, when Done is true, is status: done.

STAGE REPORT
ticket: <ticket id>
stage: <stage>
status: done | waiting | blocked
waiting_for: <only when waiting>
needs: <only when blocked>
commit: <sha>
next: <one-line handoff for the next stage>
<the stage's fields, copied from contracts.md>
END STAGE REPORT

A list field takes one item per line under it, each starting with "- ". Never shorten the verdict or the findings.
```

## Stage lines

| Stage | Stage line | Done |
|---|---|---|
| spec | `/lattice:requirement-forge <ticket>` | Shaked approved the spec, and it is committed under `.lattice/requirements/`. |
| design | `/lattice:design-blueprint <ticket>`, then run `/plan-eng-review` (always), `/plan-design-review` (UI surface), and `/plan-devex-review` (API or CLI surface) as parallel subagents | Shaked approved the design, the context doc says `status: approved`, and it is committed. |
| build (feature, new-lane) | `/lattice:code-forge <ticket> <scope>` | The code is committed, and the tests and lint ran and passed. |
| build (bug) | `/lattice:bug-fix <ticket>` | Same as build. |
| build (refactor) | `/lattice:refactor-safely <ticket>` | Same as build. |
| build (fast) | Implement `<ticket>`, then run `/lattice:review` | Same as build. |
| review | `/fresh-review:review` (add `--codex` when the build report said `codex: yes`) | The verdict and every finding are in the report. A high-risk architecture stop is status: blocked, needs: architecture go. |
| qa | `/qa` on this branch, in a real browser, with seed data only | The QA result and its evidence files exist. |
| harvest | Harvest learnings and prune the requirements index for `<ticket>` (`/lattice:learning-harvest`) | Each learning bullet has Shaked's yes, and the index is pruned or left as is. |
| ship | `/ship` — open the PR as a draft, bind it with the `ccd_pr` tools, and turn on Auto-fix | The draft PR is open, and Auto-fix is on. Never merge. |

## start_session inputs

| Input | Value |
|---|---|
| `initiation` | `user_asked` on Shaked's own turn; otherwise propose with `own_initiative` |
| `title` | `<ticket> <STAGE>: <short ticket title>` |
| `name` | `<ticket lower>-<stage>`, for example `r-3182-build` |
| `context` | `fresh` |
| `model` | `sonnet`, unless Shaked named another model |
| `use_worktree` | `true` for build, review fixes, and ship; the child works on `<branch>` |
| `background` | the ticket id, the track, and one line per finished stage with its commit |
