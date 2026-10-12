# fresh-review — Pass W (static-analysis verification)

Read this at Step 5 when Pass W is in the batch (`SA_PRESENT: 1`).

**Pass W — static-analysis verification** (any mode; `SA_PRESENT: 1` only)

This is the pass that answers *did the static-analysis tool's findings actually get handled* — for a repo whose PR gate posts Wiz, Snyk, SonarCloud, CodeQL, or similar findings as comments or checks. It is the one pass that **must** read PR context, so it does not take the isolation contract at all — it is handed the gathered findings and told to check each against the code. It runs whenever `SA_PRESENT: 1`, in every mode, launched in the same Step 5 message as the others.

Skip it when `SA_PRESENT: 0` — the PR raised no analyzer findings, or there is no PR, so there is nothing to verify and no field to fill.

Its contract, in place of the isolation contract:

> Static-analysis follow-through check on a pull request. Your one job: for each finding a static-analysis tool raised on this PR, decide whether it was **handled** — and report only the ones that were **not**.
>
> **Your inputs:**
> - `{{RUN_DIR}}/pr-context/sa-findings.md` — the tool findings gathered from the PR (bot comments, inline threads with any human replies, and relevant check runs), each labelled with the tool and, where known, a `path:line`.
> - `{{RUN_DIR}}/pr-context/review-comments.json` — the raw inline threads, so you can read the full reply chain under any finding.
> - `{{RUN_DIR}}/packet/diff.patch` — the change under review.
> - Source files under `{{SOURCE_ROOT}}` — open the flagged file/line to judge whether the issue still exists.
>
> **A finding counts as HANDLED — do not report it — when any of these is true:**
> - **Fixed in the diff.** The flagged code path was changed so the issue no longer applies. Verify against `diff.patch` and the current source, not against the tool's claim. When `scope.txt` has `DELTA=since-last-review`, the diff holds only the latest changes: a fix made before the last review is not in it, so judge by the current source.
> - **Suppressed in code.** An inline ignore directive for that tool sits on or immediately above the flagged line (e.g. a `wiz-ignore` / `nosemgrep` / `# noqa` / `sonar` suppression comment, or the tool's own documented suppression syntax). A suppression with a reason is stronger than a bare one; either counts, but note a bare suppression on a HIGH/CRITICAL finding.
> - **Dismissed in the thread.** A human (not the bot) replied under the finding accepting or dismissing it, or the tool itself marked it resolved/won't-fix. Quote the dismissing reply's author and gist in NOTES.
>
> **A finding is UNADDRESSED — report it — when none of the above holds:** the issue is still present in the code, there is no suppression, and no human dismissed it. Report it at the tool's severity if stated, else your own judgment. Do not soften a still-present HIGH finding to LOW because it is "probably fine."
>
> **Do not fix anything, do not post anything, do not edit the PR.** Diagnose only. Non-interactive: `SPAWNED_SESSION: true`; never call AskUserQuestion.
>
> **Return format — hard contract.** Write your full reasoning (every finding and its disposition) to `{{RUN_DIR}}/raw/static-analysis.md`. Return to me *only* the block below, unaddressed findings severity-ordered, maximum 25:
>
> ```
> PASS: static-analysis
> STATUS: ok | partial | failed
> TOOL: <detected tool name(s), comma-separated>
> TOTAL: <n>  FIXED: <n>  SUPPRESSED: <n>  DISMISSED: <n>  UNADDRESSED: <n>
> ---
> <CRITICAL|HIGH|MEDIUM|LOW>|<file>:<line>|static-analysis-unaddressed|<the tool's finding in one sentence>|<fix it, or add an accepted suppression / dismissal>
> ---
> NOTES: <at most three lines — e.g. which findings were dismissed and by whom>
> FILES_READ: <comma-separated paths you opened>
> ```

Two things about this pass:

- **It reports only the gaps.** A tidy PR where every Wiz finding was fixed or explicitly accepted returns `UNADDRESSED: 0` and no finding lines — that is the success case, and the counts still print in Step 8 so the reader sees the tool ran clean. Padding it with handled findings would bury the ones that matter.
- **Its unaddressed findings hit the security floor in triage.** An `UNADDRESSED` line cannot be waved into NOISE or MISREAD without naming the specific handling Pass W missed (a suppression it did not see, a reply it did not read). Absent that, it is a BLOCKER — see Step 7.

## Failure modes

- **Pass W returns UNADDRESSED findings** → each hits the static-analysis floor (Step 7) and is a blocker unless you cite the specific suppression or dismissal it missed. This is the intended path of feature 1, not a failure.
- **Pass W fails or errors** → log it with `"status":"failed"`, add `static-analysis follow-through not verified` to the reduced-coverage line, and continue. Its absence is a missing lens named in chat, never a silent pass.
