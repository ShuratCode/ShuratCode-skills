# fresh-review — Codex (Pass C)

Read this at Step 5 when `CODEX_REQUESTED: 1` and `HAS_CODEX: 1`. Keep it for the rest of the run: Steps 6 and 8.5 use it.

## Step 5: launch Pass C

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

Keep the `case` as it is: a wrong scope flag reviews the wrong commit range in silence (`pr` needs the merge-base SHA, not a branch name). Do not add a prompt — the CLI rejects one with `--base` — and do not add `--enable web_search_cached`. Even an empty diff takes about 30 seconds, so Codex must never gate the verdict on a normal-risk run.

## Step 6: join Codex

Check Codex once:

```bash
[ -f "$RUN_DIR/raw/codex.rc" ] && echo "CODEX_DONE rc=$(cat "$RUN_DIR/raw/codex.rc")" || echo "CODEX_RUNNING"
```

- **Done, rc=0** → compact it. Codex prepends repo instruction text and template scaffolding to its output, so do not read `codex.md` into your own context. Spawn one compactor subagent with `model: $MODEL_X`: *"Read `$RUN_DIR/raw/codex.md`. It contains echoed instruction text and template scaffolding before the real content — ignore all of it. Return only the Step 5 compact block with `PASS: codex`, one line per genuine finding, each with its ` ```diff ` block when Codex gave a code fix. No preamble."*
- **Done, rc≠0** → read `codex.err`, record `CODEX_FAILED: <reason>`, continue.
- **Still running past `CODEX_JOIN_BUDGET`** → when `CODEX_REASON` is `asked`, proceed without it. The verdict ships labeled Claude-only, and when the background task exits you post the addendum (Step 8.5). Nothing is killed; the work completes and lands on disk either way.
- **Still running, and the run is high-risk** (`RISK: high`, or `CODEX_REASON` is `risk` / `risk-pass`) → **do not proceed.** Codex is required here, so the budget does not apply. Say `Codex ⧗ required for a high-risk change — waiting` and wait for the background task to exit; the harness re-invokes you when it does.

## Step 8.5: Codex addendum (only when Codex landed late)

**Only reachable when Codex was launched with `CODEX_REASON: asked` on a normal-risk run.** A Codex-off run has no background task, and a high-risk run waits for Codex before the verdict, so neither enters this step.

When the background task reports completion after Step 8 has printed, compact it (Step 6) and post a short addendum — not a re-print of the whole review. Write it as a normal chat reply, with the Step 8 rules (only diffs in code blocks, file links):

```text
**Codex finished** (<duration>, after the verdict). <Verdict unchanged. | The verdict is now COMMIT-WITH-FIXES. | The verdict is now DO-NOT-COMMIT.>

- **New blockers:** <n>. **Agrees with earlier findings:** <n>. **Noise:** <n>.

<blocker items, if any, in the Step 8 shape>
```

Then update `$RUN_DIR/report.md` and set `codex.changed_verdict` in the run log. That field is what eventually answers "is Codex worth keeping" with evidence instead of a guess.
