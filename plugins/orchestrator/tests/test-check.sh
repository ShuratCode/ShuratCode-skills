#!/usr/bin/env bash

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/../scripts/orc-check.sh"
PASS=0; FAIL=0
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

G() { git -C "$REPO" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
ok()  { printf '  ok   %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL %s\n       want %s / got %s\n' "$1" "$2" "$3"; FAIL=$((FAIL + 1)); }
key() { grep "^$2:" "$1" | head -1 | sed "s/^$2: *//"; }
want() {
  local got; got="$(key "$1" "$2")"
  [ "$got" = "$3" ] && ok "$4 — $2=$3" || bad "$4" "$2=$3" "$2=$got"
}
has() {
  grep -q -- "$2" "$1" && ok "$3" || bad "$3" "line with '$2'" "$(grep '^MISSING' "$1" | tr '\n' ' ')"
}
run() { bash "$CHECK" "$TMP/report.md" "$REPO" > "$TMP/out"; }
report() { printf '%s\n' "Done. Summary above." "" "STAGE REPORT" "ticket: R-1" "$@" "END STAGE REPORT" > "$TMP/report.md"; }

REPO="$TMP/repo"
mkdir -p "$REPO/.lattice/requirements/features" "$REPO/.lattice/contexts" "$REPO/runs" "$REPO/qa"
G init -q
echo "# spec" > "$REPO/.lattice/requirements/features/token.md"
printf '# token\nstatus: approved\n' > "$REPO/.lattice/contexts/token.md"
printf '# draft\nstatus: draft\n' > "$REPO/.lattice/contexts/draft.md"
echo "# report" > "$REPO/runs/report.md"
echo "png" > "$REPO/qa/home.png"
G add -A && G commit -q -m init
SHA="$(G rev-parse --short HEAD)"

echo "no block"
echo "I am still working on it." > "$TMP/report.md"; run
want "$TMP/out" STATUS none "no block"
want "$TMP/out" CONTRACT unmet "no block"

echo "waiting and blocked"
report "stage: build" "status: waiting" "waiting_for: make test-all"; run
want "$TMP/out" CONTRACT skipped "waiting skips the contract"
report "stage: build" "status: waiting"; run
want "$TMP/out" CONTRACT unmet "waiting with no waiting_for"
report "stage: review" "status: blocked" "needs: architecture go" "verdict: ARCH-PENDING"; run
want "$TMP/out" CONTRACT skipped "ARCH-PENDING as blocked is not a failure"
want "$TMP/out" NEEDS "architecture go" "blocked names the step"
report "stage: deploy" "status: done"; run
want "$TMP/out" REASON bad_stage "unknown stage"

echo "spec"
report "stage: spec" "status: done" "commit: $SHA" "next: Run /lattice:design-blueprint for R-1." \
  "requirements: .lattice/requirements/features/token.md" "approved: yes"; run
want "$TMP/out" CONTRACT met "full spec report"
report "stage: spec" "status: done" "commit: $SHA" "next: x" \
  "requirements: .lattice/requirements/features/gone.md" "approved: no"; run
want "$TMP/out" CONTRACT unmet "spec with missing file and no approval"
has "$TMP/out" "MISSING: requirements" "names the requirements path"
has "$TMP/out" "MISSING: approved" "names the approval"

echo "design"
DESIGN=("stage: design" "status: done" "commit: $SHA" "next: Run /lattice:code-forge." \
  "plan_eng_review: done — 2 gaps settled" "plan_design_review: not-needed" "plan_devex_review: done — ok")
report "${DESIGN[@]}" "design_doc: .lattice/contexts/token.md"; run
want "$TMP/out" CONTRACT met "approved design"
report "${DESIGN[@]}" "design_doc: .lattice/contexts/draft.md"; run
has "$TMP/out" "does not say status: approved" "draft design is not done"
report "stage: design" "status: done" "commit: $SHA" "next: x" "design_doc: .lattice/contexts/token.md" \
  "plan_eng_review: not-needed" "plan_design_review: not-needed" "plan_devex_review: not-needed"; run
has "$TMP/out" "MISSING: plan_eng_review" "plan-eng-review is always required"

echo "build"
BUILD=("stage: build" "status: done" "commit: $SHA" "scope: PR 2" "lint: make lint — pass")
report "${BUILD[@]}" "tests: make test-all — pass (412 passed)" "codex: no" "next: Run /fresh-review on this branch."; run
want "$TMP/out" CONTRACT met "passing build"
report "${BUILD[@]}" "tests: make test-all — fail (3 failed)" "codex: no" "next: x"; run
has "$TMP/out" "MISSING: tests" "failing tests are not done"
report "${BUILD[@]}" "codex: no" "next: x"; run
has "$TMP/out" "MISSING: tests — missing" "tests line is required"
report "${BUILD[@]}" "tests: make test-all — pass" "codex: yes" "next: Run /fresh-review on this branch."; run
has "$TMP/out" "MISSING: next" "codex yes needs --codex in the handoff"
report "stage: build" "status: done" "commit: deadbeef" "scope: all" "lint: none" \
  "tests: pytest — pass" "codex: no" "next: x"; run
has "$TMP/out" "MISSING: commit" "unknown commit"

echo "review"
REVIEW=("stage: review" "status: done" "commit: $SHA" "next: Run /qa on this branch." \
  "should_fix: 1" "report: runs/report.md" "range: $SHA..$SHA")
report "${REVIEW[@]}" "verdict: **COMMIT-WITH-FIXES.** 0 blockers, 1 should-fix" "blockers: 0" \
  "findings:" "- The retry loop has no limit."; run
want "$TMP/out" CONTRACT met "own-branch verdict"
report "${REVIEW[@]}" "verdict: REQUEST-CHANGES. 2 blockers" "blockers: 2" "findings:" "- One."; run
has "$TMP/out" "MISSING: findings" "truncated findings"
report "${REVIEW[@]}" "verdict: LGTM" "blockers: 0" "findings: none"; run
has "$TMP/out" "MISSING: verdict" "unknown verdict word"
report "${REVIEW[@]}" "verdict: ARCH-PENDING" "blockers: 0" "findings: none"; run
has "$TMP/out" "ARCH-PENDING is a stop" "ARCH-PENDING with status done"
report "${REVIEW[@]}" "verdict: APPROVE" "blockers: 0" "findings: none" "stack_unit: yes"; run
has "$TMP/out" "MISSING: stack_report" "stack unit needs its STACK REPORT line"
report "${REVIEW[@]}" "verdict: APPROVE" "blockers: 0" "findings: none" "stack_unit: yes" \
  "stack_report: STACK REPORT — s42 · unit 1/3 · PRs #42, #43 · APPROVE · blockers 0"; run
want "$TMP/out" CONTRACT met "stack unit with its line"
report "${REVIEW[@]}" "verdict: APPROVE" "blockers: 0" "findings: none" "stack_unit: yes" \
  "stack_report: unit 1 approved"; run
has "$TMP/out" "STACK REPORT shape" "malformed STACK REPORT"

echo "qa, harvest, ship"
report "stage: qa" "status: done" "commit: $SHA" "next: x" "result: pass" "env: stg" \
  "evidence:" "- qa/home.png" "bugs: none"; run
want "$TMP/out" CONTRACT met "qa with evidence"
report "stage: qa" "status: done" "commit: $SHA" "next: x" "result: pass" "env: stg" \
  "evidence: qa/missing.png" "bugs: none"; run
has "$TMP/out" "MISSING: evidence" "missing evidence file"
report "stage: harvest" "status: done" "commit: $SHA" "next: Run /ship." "learnings: 0" "index: unchanged"; run
want "$TMP/out" CONTRACT met "harvest with zero learnings"
report "stage: ship" "status: done" "commit: $SHA" "next: x" "pr: https://github.com/o/r/pull/7" \
  "head: $SHA" "ci: pending" "draft: no" "autofix: on"; run
has "$TMP/out" "MISSING: draft" "ship must open a draft"

echo "the last block wins"
{ printf '%s\n' "STAGE REPORT" "ticket: R-1" "stage: build" "status: waiting" "waiting_for: tests" "END STAGE REPORT"
  printf '%s\n' "STAGE REPORT" "ticket: R-1" "stage: harvest" "status: done" "commit: $SHA" "next: x" "learnings: 1" "index: pruned" "END STAGE REPORT"
} > "$TMP/report.md"; run
want "$TMP/out" STAGE harvest "last block is read"

echo "contracts file drives required fields"
sed 's/^| `index` |.*/&\n| `owner` | who approved |/' "$HERE/../skills/orchestrator/references/contracts.md" > "$TMP/contracts.md"
report "stage: harvest" "status: done" "commit: $SHA" "next: x" "learnings: 0" "index: unchanged"
ORC_CONTRACTS="$TMP/contracts.md" bash "$CHECK" "$TMP/report.md" "$REPO" > "$TMP/out"
has "$TMP/out" "MISSING: owner" "a new row becomes required"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
