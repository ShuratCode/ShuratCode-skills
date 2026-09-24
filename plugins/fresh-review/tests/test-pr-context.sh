#!/usr/bin/env bash
# test-pr-context.sh — fixtures for fr-pr-context.sh, Step 4.7's producer-side
# gather. It fetches the PR description, discussion, and static-analysis bot
# findings into pr-context/ for triage and Pass W — and NEVER for the isolated
# passes.
#
# gh is stubbed on PATH so the whole script runs offline: the stub answers
# `pr view`, `repo view`, and `api …/comments` / `api …/check-runs` from fixture
# files. The traps this exists to catch, in order of how quietly they fail:
#
# 1. Missing a real static-analysis finding. A Wiz/Snyk/CodeQL comment, an inline
#    thread, or a failing check from a known tool must set SA_PRESENT=yes and name
#    the tool — otherwise Pass W never runs and an unaddressed finding ships.
# 2. Flagging a non-tool bot. dependabot/renovate raise PRs, not findings to
#    disposition; treating them as static analysis would launch Pass W on noise.
# 3. Losing the human dismissal. A reply under a bot finding must travel with the
#    finding (grouped by in_reply_to_id) so Pass W can see it was dismissed.
# 4. Failing loud on a no-PR branch. No PR is the normal pre-commit case and must
#    be a clean PR_CONTEXT=none, never an error that stops the run.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HERE/../scripts"
[ -f "$SCRIPTS/fr-pr-context.sh" ] || { echo "cannot find fr-pr-context.sh next to $HERE"; exit 2; }
command -v python3 >/dev/null || { echo "python3 required"; exit 2; }

PASS=0; FAIL=0
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

ok()  { printf '  ok   %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL %s\n       want %s / got %s\n' "$1" "$2" "$3"; FAIL=$((FAIL + 1)); }

key() { printf '%s\n' "$1" | grep "^$2:" | head -1 | sed "s/^$2: //"; }
want() { # output key expected label
  local got; got="$(key "$1" "$2")"
  [ "$got" = "$3" ] && ok "$4 — $2=$3" || bad "$4" "$2=$3" "$2=$got"
}
contains() { # output key needle label
  case "$(key "$1" "$2")" in
    *"$3"*) ok "$4 — $2 contains $3" ;;
    *) bad "$4" "$2 ~ $3" "$2=$(key "$1" "$2")" ;;
  esac
}

# A gh stub that answers from fixture files named by env. GH_FAIL=1 makes
# `gh pr view` exit non-zero, standing in for a branch with no PR.
make_gh() { # dir
  local bin="$1/bin"; mkdir -p "$bin"
  cat > "$bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view")
    [ "${GH_FAIL:-0}" = "1" ] && { echo "no pull requests found" >&2; exit 1; }
    cat "$GH_PR_JSON" ;;
  "repo view") printf '%s\n' "${GH_SLUG:-o/r}" ;;
  "api "*|"api")
    case "$*" in
      *"/comments"*)   cat "$GH_REVIEW_COMMENTS" ;;
      *"/check-runs"*) cat "$GH_CHECK_RUNS" ;;
      *) printf '[]\n' ;;
    esac ;;
  *) echo "gh stub: unhandled: $*" >&2; exit 3 ;;
esac
STUB
  chmod +x "$bin/gh"
  printf '%s' "$bin"
}

# Run fr-pr-context.sh with the stub on PATH. Fixtures for the run live in
# $TMP/<run-name>/fixtures/{pr,review-comments,check-runs}.json, written by the
# caller before this is called. The run dir is $TMP/<run-name>, known to the
# parent shell, so assertions can read pr-context/ afterwards even though this
# runs inside a command substitution.
run_ctx() { # run-name  [GH_FAIL]
  local run="$TMP/$1"; mkdir -p "$run/packet" "$run/raw"
  {
    echo "RUN_DIR='$run'"
    echo "PR_NUMBER='${PR_NUMBER:-}'"
    echo "PR_HEAD='${PR_HEAD:-}'"
    echo "STACK_PRS='${STACK_PRS:-}'"
  } > "$run/state.env"
  local bin; bin="$(make_gh "$run")"
  PATH="$bin:$PATH" \
    GH_PR_JSON="$run/fixtures/pr.json" \
    GH_REVIEW_COMMENTS="$run/fixtures/review-comments.json" \
    GH_CHECK_RUNS="$run/fixtures/check-runs.json" \
    GH_SLUG="o/r" GH_FAIL="${2:-0}" \
    bash "$SCRIPTS/fr-pr-context.sh" "$run"
}

# ---------------------------------------------------------------------------
# 1. A PR carrying Wiz (comment), Snyk (inline thread + human dismissal), and
#    CodeQL (failing check). All three must be detected; the dismissal reply must
#    be grouped under the Snyk finding.
# ---------------------------------------------------------------------------
FX="$TMP/case1/fixtures"; mkdir -p "$FX"
cat > "$FX/pr.json" <<'JSON'
{"number":487,"url":"https://x/pull/487","state":"OPEN","title":"t","headRefOid":"deadbeef",
 "body":"Wires the ingestion signal.",
 "comments":[
   {"author":{"login":"alice"},"body":"Looks good."},
   {"author":{"login":"wiz-inc[bot]"},"body":"WIZ-001: hardcoded secret. HIGH."},
   {"author":{"login":"dependabot[bot]"},"body":"Bumps lodash 4.17.20 to 4.17.21."}
 ],
 "reviews":[{"author":{"login":"bob"},"state":"CHANGES_REQUESTED","body":"add a test"}]}
JSON
cat > "$FX/review-comments.json" <<'JSON'
[
  {"id":1,"user":{"login":"snyk-bot"},"body":"SNYK: SQLi risk.","path":"src/db.py","line":42,"in_reply_to_id":null},
  {"id":2,"user":{"login":"alice"},"body":"false positive, validated upstream","path":"src/db.py","line":42,"in_reply_to_id":1},
  {"id":3,"user":{"login":"carol"},"body":"nit: rename","path":"src/x.py","line":5,"in_reply_to_id":null}
]
JSON
cat > "$FX/check-runs.json" <<'JSON'
{"check_runs":[
  {"name":"CodeQL","app":{"slug":"github-advanced-security"},"conclusion":"failure","output":{"title":"2 alerts","summary":"path traversal"}},
  {"name":"unit-tests","app":{"slug":"github-actions"},"conclusion":"success","output":{}}
]}
JSON
OUT="$(run_ctx case1)"
CTX="$TMP/case1/pr-context"
want "$OUT" PR_CONTEXT present "wiz+snyk+codeql PR"
want "$OUT" SA_PRESENT yes "wiz+snyk+codeql PR"
want "$OUT" SA_SIGNAL 3 "three tool findings (comment+thread+check)"
contains "$OUT" SA_TOOL wiz "wiz detected"
contains "$OUT" SA_TOOL snyk "snyk detected"
contains "$OUT" SA_TOOL codeql "codeql detected"
# dependabot must NOT be treated as static analysis.
case "$(key "$OUT" SA_TOOL)" in
  *dependabot*) bad "dependabot excluded" "SA_TOOL without dependabot" "$(key "$OUT" SA_TOOL)" ;;
  *) ok "dependabot excluded from SA_TOOL" ;;
esac
# The human dismissal must be grouped under the snyk finding in sa-findings.md.
if grep -q "false positive, validated upstream" "$CTX/sa-findings.md"; then
  ok "human dismissal reply travels with the snyk finding"
else
  bad "dismissal grouping" "reply in sa-findings.md" "absent"
fi
# body.md and discussion.md must be written for triage.
[ -s "$CTX/body.md" ] && ok "body.md written" || bad "body.md" "non-empty" "empty/missing"
[ -s "$CTX/discussion.md" ] && ok "discussion.md written" || bad "discussion.md" "non-empty" "missing"

# ---------------------------------------------------------------------------
# 2. A PR with only human discussion — no analyzer findings. Context is present,
#    but Pass W must not run.
# ---------------------------------------------------------------------------
FX2="$TMP/case2/fixtures"; mkdir -p "$FX2"
cat > "$FX2/pr.json" <<'JSON'
{"number":12,"url":"https://x/pull/12","state":"OPEN","title":"t","headRefOid":"cafe",
 "body":"small refactor","comments":[{"author":{"login":"alice"},"body":"lgtm"}],"reviews":[]}
JSON
printf '[]\n' > "$FX2/review-comments.json"
printf '{"check_runs":[]}\n' > "$FX2/check-runs.json"
OUT="$(run_ctx case2)"
want "$OUT" PR_CONTEXT present "human-only PR"
want "$OUT" SA_PRESENT no "human-only PR — no Pass W"
want "$OUT" SA_TOOL none "human-only PR — no tool"

# ---------------------------------------------------------------------------
# 3. No PR for the branch — clean skip, never an error.
# ---------------------------------------------------------------------------
FX3="$TMP/case3/fixtures"; mkdir -p "$FX3"
printf '{}\n' > "$FX3/pr.json"
printf '[]\n' > "$FX3/review-comments.json"
printf '{"check_runs":[]}\n' > "$FX3/check-runs.json"
OUT="$(run_ctx case3 1)"
want "$OUT" PR_CONTEXT none "no PR for branch"
want "$OUT" SA_PRESENT no "no PR — no static analysis"

mkdir -p "$TMP/case4"
cp -R "$FX" "$TMP/case4/fixtures"
OUT="$(PR_NUMBER=487 STACK_PRS="486 487" run_ctx case4)"
CTX="$TMP/case4/pr-context"
want "$OUT" PR_CONTEXT present "a stack unit of two PRs"
want "$OUT" SA_SIGNAL 6 "a stack unit gathers tool findings from every PR"
grep -q "^## PR #486" "$CTX/body.md" && grep -q "^## PR #487" "$CTX/body.md" \
  && ok "body.md has one section per PR" || bad "stacked body.md" "a section per PR" "$(head -3 "$CTX/body.md")"
grep -q "PR #486 tool thread" "$CTX/sa-findings.md" \
  && ok "sa-findings.md names the PR of each finding" || bad "stacked sa-findings.md" "PR tag" "missing"
python3 -c 'import json,sys; t=json.load(open(sys.argv[1])); assert {x["pr"] for x in t} == {486, 487}' \
  "$CTX/review-comments.json" && ok "review-comments.json merges threads from every PR" \
  || bad "stacked review-comments.json" "threads tagged 486 and 487" "$(head -c 200 "$CTX/review-comments.json")"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
