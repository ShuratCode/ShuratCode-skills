# fresh-review — run log

Read this at Step 10. Write `$RUN_DIR/run.json` in this shape:

```json
{"skill":"fresh-review","schema":13,"run_id":"<RUN_ID>","plugin_version":"<FR_VERSION>",
 "ts_start":"<TS_START>","ts_end":"<now>","duration_s":0,
 "repo":"<repo>","branch":"<BRANCH>","base":"<BASE>",
 "mode":"<review|pr>","codex_requested":false,"codex_reason":"<none|asked|risk|risk-pass>",
 "army_requested":false,"lattice_context":false,
 "architecture":{"gate":"<approved|waived|trivial|carried|pending|skipped|failed>","decisions":0,"diagram":"<class,sequence,flow|none>","questions":0,"rounds":0},
 "comments":{"blocks":0,"lines":0},
 "pr":{"number":0,"url":"","state":"","head":"","drift":false},
 "stack":{"id":"<STACK_ID>","unit":1,"units":1,"prs":[0]},
 "delta":{"requested":true,"applied":true,"reason":"<DELTA_REASON>","source":"<record|runs_index|none>","kind":"<fast_forward|rebased>",
          "prior_run":"<DELTA_PRIOR_RUN>","prior_head":"<DELTA_PRIOR_HEAD>","prior_blockers":0,"fixed":0,"open":0,"released":0},
 "pr_context":{"present":false,"comments":0,"reviews":0,"threads":0,"discussion_lines":0},
 "scope":"<REVIEW_SCOPE>","diff_base":"<DIFF_BASE>","checkpoint":"<CHECKPOINT_SHA>",
 "risk":"<RISK>","risk_level":"<low|med|high>",
 "static_analysis":{"present":false,"tool":"","total":0,"fixed":0,"suppressed":0,"dismissed":0,"unaddressed":0},
 "ui_preview":{"frontend":false,"reason":"<UI_REASON>"},
 "diff":{"files":0,"lines":0},
 "passes":[
   {"name":"understanding","status":"ok","duration_s":0,"change_kind":"<behavior|structure|trivial>","isolation":"clean",
    "vocab":"<ddd-principles|atom-defaults>","title_mismatch":false},
   {"name":"implementation","status":"ok","duration_s":0,"findings":0,"isolation":"clean"},
   {"name":"lattice","status":"ok","duration_s":0,"findings":0,"isolation":"clean"},
   {"name":"cso","status":"ok","duration_s":0,"findings":0,"isolation":"clean"},
   {"name":"review","status":"ok","duration_s":0,"findings":0},
   {"name":"static-analysis","status":"ok","duration_s":0,"tool":"","unaddressed":0},
   {"name":"fix-check","status":"ok","duration_s":0,"fixed":0,"open":0,"isolation":"clean"},
   {"name":"codex","status":"ok","duration_s":0,"findings":0,"changed_verdict":false},
   {"name":"risk","status":"ok","duration_s":0,"risk_level":"<low|med|high>","isolation":"clean"}],
 "triage":{"real_bug":0,"should_fix":0,"by_design":0,"noise":0,"misread":0,"deduped":0},
 "verdict":"<VERDICT>","handoff_rc":0,
 "tools":{"gstack":0,"codex":0,"gh":0}}
```

- **Set `architecture` from Step 4.8.** It keeps its old name so old and new entries line up. `gate` is `skipped` under `--understood`, `failed` when Pass U failed, `trivial` for a trivial change, `carried` when the user understood the last review and the delta has no new parts, `waived` when the user waived the check, `approved` when the user's answer held the key points, and `pending` when the run stopped at the check. `decisions` is Pass U's NEW_PARTS count; `diagram` is which diagrams were shown, as a comma-separated list in the order `class,sequence,flow` (for example `sequence,flow`), or `none`; `questions` is how many check questions were asked; `rounds` is how many follow-up rounds it took (0 when the first answer held every key point). Omit the `understanding` pass when the gate was skipped. When the gate stayed `pending`, the implementation passes never launched — omit them, and set `verdict` to `ARCH-PENDING`.
- **Set `lattice_context` from Step 4.4, and `army_requested` from `ARMY_REQUESTED`.** Omit the `lattice` pass when `lattice_context` is false, and the `review` pass when `army_requested` is false or outside pr-remote — a pass that never launched is not a pass that failed. A later re-review reads these two keys to decide which lenses the run should have had.
- **`comments`** is `COMMENT_BLOCKS` and `COMMENT_LINES` from Step 4.4.
- **`triage.should_fix`** counts bucket 5.
- Set `codex_requested` from the final `CODEX_REQUESTED` in `state.env` (after Step 4 and Step 6 may have forced it), and `codex_reason` from `CODEX_REASON`. It is what tells cross-run analysis apart: a `codex` pass absent because it was never asked for versus one dropped because it failed.
- **Omit the `codex` pass from `passes[]` when `codex_requested` is `false`** — a pass that never launched is not a pass that failed, and `codex_requested` already records the choice. When it was requested but failed or was unavailable, keep the entry with `"status":"failed"` so the failure stays visible.
- **Add `delta` only when `--delta` was requested.** `applied` is `DELTA: applied`; `reason` is `DELTA_REASON` (empty when applied). `fixed` and `open` are Pass F's counts after triage; `released` is how many OPEN lines left bucket 1 under the prior-blocker floor (they count as fixed too). Omit `kind`, `prior_run`, `prior_head`, and the counts when the delta was not applied. Omit the `fix-check` pass when Pass F did not launch; keep it with `"status":"failed"` when it launched and failed. `diff` then counts the delta, not the whole PR.
- **Add `stack` only for a stack unit** — when the handoff gave a stack id. Take `id`, `unit`, and `units` from the handoff and `prs` from `STACK_PRS`. The orchestrator's own entry (`mode: "stack"`) is written by `fr-stack.sh` and carries the whole plan instead.
- Omit `pr` outside pr-remote mode, and the `risk` pass outside `pr` mode — an absent pass and a failed one must stay distinguishable. Likewise omit `risk_level` (top-level) and the `ui_preview` object outside `pr` mode; they are pr-mode artifacts. `risk` (the mechanical class) is always present.
- **Keep the mechanical `risk` and Pass K's `risk_level` distinct.** `risk` is `normal`/`high` from `fr-packet.sh`'s pattern count and gates `/cso` depth; `risk_level` is Pass K's `low`/`med`/`high` judgment and is what the header shows. In `review` mode `risk_level` is absent and only `risk` exists. When the `risk` pass failed, keep its entry with `"status":"failed"` and omit `risk_level`.
- **Omit the `static-analysis` pass and set `static_analysis.present:false` when `SA_PRESENT: 0`** — the PR raised no analyzer findings, or there was no PR, so the pass never launched. When it ran, fill `static_analysis` from Pass W's `TOOL` / `TOTAL` / `FIXED` / `SUPPRESSED` / `DISMISSED` / `UNADDRESSED` counts and keep the pass entry; keep it with `"status":"failed"` if it launched and failed. `unaddressed` is the count that became blockers.
- **Set `pr_context` from `fr-pr-context.sh`.** `present:false` when `PR_CONTEXT` was `none` or `unavailable`; otherwise fill `comments` / `reviews` / `threads` / `discussion_lines` from its keys. It records whether the producer had the PR's discussion to triage against, independent of whether any static-analysis pass ran.
- `ui_preview.frontend` is whether the diff touched UI (`fr-ui-detect.sh`'s `FRONTEND_HITS > 0`), and `reason` is the `UI_REASON`. Step 4.6 never launches, so there is no `shown`/`eligible` to record.
- `tools.codex` stays availability (`HAS_CODEX`), independent of whether the run requested Codex.

Then:

```bash
. "$RUN_DIR/state.env"; FR_STATUS="$STATUS" bash "${CLAUDE_PLUGIN_ROOT}/scripts/fr-log.sh" "$RUN_DIR"
```

The script validates the JSON, appends it as one line to `$LOG_DIR/runs.jsonl`, prunes old run directories to `FR_RUN_RETENTION`, and pings the gstack timeline. Validation **gates** the append rather than following it: a malformed line in `runs.jsonl` breaks every future analysis of it. On `RUN_JSON: invalid`, `$RUN_DIR/run.json` is kept — tell the user the index entry was skipped, and why.

Fill the zeroed fields from the actual run — per-pass wall time, per-pass finding counts, and the triage bucket counts. Those are the point of the log, not decoration.
