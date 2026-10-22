# fresh-review — stack mode

Read this only when `MODE` is `stack`. Step S replaces every SKILL.md step after Step 1, except for a stack of one PR, which goes back to a normal `--pr` run.

## Stack mode (orchestrator)

A stack is a chain of PRs where each PR's base branch is the head branch of the PR below it. `--stack` turns this session into an **orchestrator**. It reviews no code. It does three things, then stops:

1. **Analyze.** `fr-stack.sh` maps the stack and measures every PR on its own delta (from the PR below it, not from `main`). It uses the same packet script and the same risk rule as a review, so it sees counts, never a diff.
2. **Decide.** It groups the PRs, bottom to top, into **review units**. A unit is one PR, or a run of adjacent PRs reviewed as one change.
3. **Hand off.** It prints one handoff prompt per unit in chat. **The user runs each unit in a new session, by hand**, and pastes the handoff there. This skill never starts a session, and never gives a command that starts one: the user decides where, when, and in what order each review runs.
4. **Track.** The orchestrator session stays open. Each review ends with a `STACK REPORT` line; the user pastes it back here, and the orchestrator records it and shows where the stack stands.

**A stack of one PR is not handed off.** There is nothing to plan, so the script says `NEXT: review_here` and the review runs in this session as a normal `--pr` review.

**Why a new session per unit, and not subagents here** (stacks of two or more PRs). This session has read the PR titles and the plan. A review producer that knows the author's claims triages with that bias, and a review is itself a full orchestration — its own subagents, its own risk tier, its own stop for approval on a high tier. One session per unit keeps each review blind to the others and gives each one its own context budget.

**The grouping rules** (in `fr-stack.sh`, applied bottom to top). A PR joins the unit below it only when **all** of these hold:

- it is **linked**: its base branch is the head branch of the PR below it;
- neither it nor the unit below is `RISK: high`, and the **combined** diff is not `RISK: high` either — checked by running the packet script on the combined range. A high-risk PR is always reviewed alone. So a combined review never forces Codex or `/cso --comprehensive` that the parts would not;
- **and** one of: it is small (`FR_STACK_SMALL_LINES`, default 80 changed lines), the unit below is small, or at least half of the smaller file set is shared (a follow-up to the same code).

Otherwise it starts a new unit. Every decision carries a one-line reason, which goes to the plan and the handoff.

**A re-review of a unit** uses its re-review handoff, which is the same handoff plus `--delta` (see `delta.md`).

**A combined unit is one pr-remote review of a range.** Its handoff runs `--pr <top> --since-pr <bottom>`. `fr-pr-resolve.sh` walks the stack down from the top PR to the bottom one, and the diff runs from the bottom PR's base branch to the top PR's head. Step 4.7 gathers the description, discussion, and static-analysis findings of **every** PR in the unit, so Pass W checks them all.

## Step S: Orchestrate the stack (stack mode only)

Skip unless `MODE` is `stack`. This step is the whole run in stack mode: no checkpoint, no packet, no gate, no reviewer. It never edits the tree.

```bash
. "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-stack.sh" "$RUN_DIR"
```

On `STACK: unresolved`, stop and say why. `REASON` is one of `gh_missing`, `no_stack_ref`, `bad_stack_ref`, `foreign_repo`, `gh_pr_list_failed`, `gh_pr_view_failed`, `pr_fetch_failed`, `no_merge_base`, or `stack_script_failed` (the script's stderr has the detail). Never fall back to reviewing one PR here.

On `STACK: resolved` with `NEXT: review_here`, the stack is one PR. Do not print a plan or a handoff. Say `Stack of one PR (#<n>) — reviewing it here.`, then run Step 1 again with `REVIEW_ARGS` as the flags (it is `--pr <n>`, plus `--codex` and `--army` when this run had them) and follow the normal pr-remote flow from Step 1.5. The stack run directory is left as it is; the review has its own.

On `STACK: resolved` with `NEXT: handoff`, print the plan, then the handoffs, and stop:

1. **The plan.** Print `$STACK_PLAN` (`stack/plan.md`) verbatim. It is short: the stack order, then one row per unit with its PRs and titles, size, risk, and why. When `FORK_AT` is not `none`, the stack branches above that PR and only the path to the given PR was planned — say so, and say that `--stack` with explicit refs plans a different branch.
2. **The handoffs.** For each unit `k`, print a `Unit <k> of <n>` heading, then its handoff file (`$STACK_HANDOFF_DIR/unit-<k>.md`) verbatim in a plain ` ``` ` fence, so the user can copy it in one click. Then say, once: `When a unit is done, paste its STACK REPORT line here.` Do not start sessions, do not offer to start them, and do not print shell commands that start them. Never start a review in this session.
3. **Log.** `fr-stack.sh` has already written `run.json` (`mode: "stack"`, `verdict: "HANDOFF"`). Append it to the index:

   ```bash
   . "$RUN_DIR/state.env"; FR_STATUS=handoff bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-log.sh" "$RUN_DIR"
   ```

4. **Track progress.** The run stays open for the user's reports. When the user pastes a `STACK REPORT` line, or says it in words ("unit 2 is done, request changes, 3 blockers"; "skip unit 4"), record it:

   ```bash
   . "$RUN_DIR/state.env"; bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-stack-status.sh" "$RUN_DIR" <unit> <verdict> <blockers>
   ```

   `<verdict>` is the unit's verdict (`APPROVE`, `APPROVE-WITH-COMMENTS`, `REQUEST-CHANGES`, `ARCH-PENDING`) or `SKIPPED`. A unit may be reported again — after fixes, the new verdict replaces the old one. With no unit, the script only prints the status. Then print the status as a short table (unit, PRs, verdict, blockers), then `Stack: <STACK_VERDICT> (<REPORTED> reported)`.

   `STACK_VERDICT` is `REQUEST-CHANGES` as soon as one unit has it, `pending` while any unit is unreported or waits for architecture approval, `INCOMPLETE` when all reported but one was skipped, and otherwise the weakest verdict of the units. When the stack is complete, name the PRs that still carry blockers. The script only records what the user reports: never read a unit's run directory, and never fill in a verdict nobody reported.

   `REASON` on an error is `no_stack_status` (wrong run directory), `no_such_unit`, `bad_verdict`, or `bad_blockers`. Ask the user to correct the report.

5. **Re-review a unit.** When a unit comes back `REQUEST-CHANGES`, say once: `When the fixes are pushed, ask me to re-review unit <k>.` When the user asks ("re-review unit 2", "unit 2 has fixes"), print a `Unit <k> of <n> — re-review` heading and the file `$STACK_HANDOFF_DIR/unit-<k>-rereview.md` verbatim in a plain fence. It is the unit's handoff plus `--delta`: the new session reviews only what changed since that unit's last review and checks the earlier blockers. Its `STACK REPORT` line replaces the unit's old verdict, as in item 4. Never start the re-review here.

Rules for this step:

- **Do not change the plan by hand.** The grouping is mechanical so that it is the same on every run and testable. If the user wants a different split, they say so and you re-run with the refs they want (`--stack "41,42"` and `--stack "43"`, for example).
- **Do not add to the handoffs.** No PR titles, no summary of what a PR does, no view on the code. The handoff carries scope and mechanics only. Anything more reaches the review producer as the author's claim, and the next review triages against it.
- **The units are independent.** They may run in any order or at the same time. Each one sets its own risk tier, and stops for approval on a high tier.
- **`--codex` and `--army` carry over** to every handoff when this run had them. `--understood` never does: each unit's approval is its own.
- **A re-review keeps the unit as planned.** Do not re-plan the stack to re-review one unit. If the user restacked and a re-review handoff fails with `since_pr_not_below`, re-run the orchestrator.

## Failure modes

- **`STACK: unresolved`** → stop and print `REASON` (Step S). Never fall back to reviewing a single PR in the orchestrator session.
- **The stack branches** (`FORK_AT` is set) → not an error. Plan the path to the given PR, say where it branches, and tell the user to run `--stack` with explicit refs for another branch.
- **A stack report the status script refuses** (`STATUS: error`) → say which part is wrong and ask the user for a corrected report. Never guess a unit or a verdict.
- **The orchestrator session was closed** → the status file survives in the stack's run directory. In a new session, run `fr-stack-status.sh` on that directory to see where the stack stands and keep reporting.
- **A stack of one PR** (`NEXT: review_here`) → no plan, no handoff. Re-run Step 1 with `REVIEW_ARGS` and review the PR in this session.
- **`since_pr_not_below`** → the handoff is stale (the stack was restacked) or hand-typed wrong. Re-run the stack orchestrator to get fresh handoffs.

## Examples

**"review the stack for PR 43"** → `--stack "43"`. Step S plans the units and prints one handoff per unit. Each unit sets its own risk tier in its own session.

**"re-review unit 2"** in the orchestrator session → Step S prints `unit-2-rereview.md`. The user pastes it in a new session; its `STACK REPORT` line replaces unit 2's old verdict.
