# Completion contracts

Each child ends its final turn with one `STAGE REPORT` block. The parent checks the block with `scripts/orc-check.sh`. Edit this file to change what a stage must return. Keep each field on its own line, in `key: value` form.

## The block

```
STAGE REPORT
ticket: R-3182
stage: build
status: done
commit: 4f2c9a1
next: Run /fresh-review on this branch.
<stage fields below>
END STAGE REPORT
```

Common fields, every stage:

| Field | Rule |
|---|---|
| `ticket` | the ticket id, for example `R-3182` |
| `stage` | one of `spec`, `design`, `build`, `review`, `qa`, `harvest`, `ship` |
| `status` | `done`, `waiting`, or `blocked` |
| `waiting_for` | required when `status: waiting` — what will wake the child |
| `needs` | required when `status: blocked` — the exact step Shaked must take |
| `commit` | the commit that holds the stage's output; must resolve in the repo |
| `next` | the one-line handoff for the next stage |

The parent checks a contract only when `status: done`.

A field can hold a list. Put each item on its own line under the field, starting with `- `:

```
findings:
- The token refresh drops the tenant id, so a second tenant reads the first one's data.
- The retry loop has no limit.
```

A row whose rule starts with `optional` or `required when` is not checked as always required. `scripts/orc-check.sh` reads the field names from the tables in this file, so a new row here becomes a required field. A new rule that needs more than "present" (a path that must exist, a fixed set of words) also needs a line in the script.

## spec

| Field | Rule |
|---|---|
| `requirements` | one or more paths under `.lattice/requirements/`; each must exist |
| `approved` | `yes` — Shaked approved the spec in the child session |

## design

| Field | Rule |
|---|---|
| `design_doc` | a path under `.lattice/contexts/`; must exist and hold `status: approved` |
| `plan_eng_review` | `done` and its result in one line |
| `plan_design_review` | `done` and its result, or `not-needed` (no UI surface) |
| `plan_devex_review` | `done` and its result, or `not-needed` (no API or CLI surface) |

## build

| Field | Rule |
|---|---|
| `scope` | which part of the PR split this child built, or `all` |
| `tests` | the command that ran and its result: `make test-all — pass (412 passed)` |
| `lint` | the command and its result, or `none` |
| `codex` | `yes` when the diff touches auth, IaC, migration, or cross-account code; the `next` line then asks for `--codex` |

A `tests` result of `fail` or `not-run` is not done. The child sets `status: blocked` or keeps working.

## review

| Field | Rule |
|---|---|
| `verdict` | the full verdict line, starting with one of `COMMIT`, `COMMIT-WITH-FIXES`, `DO-NOT-COMMIT`, `APPROVE`, `APPROVE-WITH-COMMENTS`, `REQUEST-CHANGES` |
| `blockers` | a number |
| `should_fix` | a number |
| `findings` | one plain sentence per finding, or `none` |
| `report` | the path to fresh-review's `report.md`; must exist |
| `range` | the reviewed range, `<base sha>..<head sha>` |
| `stack_unit` | optional: `yes` when the child reviews one unit of a fresh-review stack |
| `stack_report` | required when `stack_unit: yes`: the exact `STACK REPORT — <stack id> · unit k/n · PRs … · <verdict> · blockers N` line |

A high-risk architecture stop is `status: blocked`, `needs: architecture go`, and, for a stack unit, the verdict `ARCH-PENDING`. It is not a failure, and the parent never answers it.

When `blockers` is more than 0, `findings` must have at least that many lines.

## qa

| Field | Rule |
|---|---|
| `result` | `pass`, `fail`, or `pass-with-fixes` |
| `env` | where it ran: `local`, `stg` |
| `evidence` | paths to the QA report and screenshots; each must exist |
| `bugs` | one line per bug found and the commit that fixed it, or `none` |

## harvest

| Field | Rule |
|---|---|
| `learnings` | the number of bullets Shaked approved (may be `0`) |
| `index` | `pruned` or `unchanged` |

## ship

| Field | Rule |
|---|---|
| `pr` | the PR URL |
| `head` | the head SHA |
| `ci` | the CI state |
| `draft` | `yes` |
| `autofix` | `on` |

## On a miss

1. First miss: the parent sends the same child one `SendMessage` that names each missing or wrong field.
2. Second miss: the parent stops the stage and reports both reports and the missing fields to Shaked. No third message.
