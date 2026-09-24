#!/usr/bin/env bash
# fr-review-record.sh <RUN_DIR> <VERDICT> <full|reduced> — Step 10, pr-remote only.
# Reads $RUN_DIR/blockers.json (a JSON array of the run's open blockers).
#
# Output contract (stdout):
#   === FRESH-REVIEW RECORD ===
#   RECORD: written | failed
#   REASON: <slug>                   (only when failed)
#   KEY / HEAD / BLOCKERS            (only when written)
#   === END ===

set -u

USAGE="usage: fr-review-record.sh <RUN_DIR> <VERDICT> <full|reduced>"
RUN_DIR="${1:?$USAGE}"
VERDICT="${2:?$USAGE}"
COVERAGE="${3:?$USAGE}"
STATE="$RUN_DIR/state.env"
set -a
# shellcheck disable=SC1090
. "$STATE"
set +a

failed() {
  printf '%s\n' "=== FRESH-REVIEW RECORD ===" "RECORD: failed" "REASON: $1" "=== END ==="
  exit 0
}

[ -n "${REVIEW_KEY:-}" ] && [ -n "${PR_HEAD:-}" ] && [ -n "${PR_MERGE_BASE:-}" ] || failed not_pr_remote
case "$VERDICT" in
  APPROVE|APPROVE-WITH-COMMENTS|REQUEST-CHANGES) : ;;
  *) failed bad_verdict ;;
esac
case "$COVERAGE" in
  full|reduced) : ;;
  *) failed bad_coverage ;;
esac

case "${ARCH_APPROVED:-0}:${ARCH_GATE:-}:${DELTA:-}:${DELTA_PRIOR_ARCH_GATE:-}" in
  1:*|*:approved:*|*:carried:*|*:not_needed:applied:approved|*:failed:applied:approved) ARCH_RECORD=approved ;;
  *) ARCH_RECORD="${ARCH_GATE:-none}" ;;
esac
export ARCH_RECORD

mkdir -p "$LOG_DIR/reviews"
RECORD="$LOG_DIR/reviews/$REVIEW_KEY.json"
ARCH_FILE="$LOG_DIR/reviews/$REVIEW_KEY.architecture.md"
COUNT=$(python3 - "$RUN_DIR/blockers.json" "$RECORD.tmp" "$VERDICT" "$COVERAGE" <<'PY'
import json, os, sys, time
blockers_path, out, verdict, coverage = sys.argv[1:5]
required = ("severity", "file", "line", "category", "problem", "fix")
blockers = json.load(open(blockers_path))
if not isinstance(blockers, list):
    sys.exit(1)
for item in blockers:
    if not isinstance(item, dict) or any(key not in item for key in required):
        sys.exit(1)
env = os.environ
record = {
    "key": env["REVIEW_KEY"], "pr": int(env["PR_NUMBER"]),
    "since_pr": int(env["SINCE_PR"]) if env.get("SINCE_PR") else None,
    "run_id": env["RUN_ID"], "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "head": env["PR_HEAD"], "base": env["PR_MERGE_BASE"], "verdict": verdict,
    "coverage": coverage, "risk": env.get("RISK", ""), "arch_gate": env["ARCH_RECORD"],
    "blockers": blockers,
}
json.dump(record, open(out, "w"), indent=1)
print(len(blockers))
PY
) || { rm -f "$RECORD.tmp"; failed bad_blockers; }

PRIOR_ARCH="$RUN_DIR/delta/prior-architecture.md"
CURRENT_ARCH="$RUN_DIR/raw/architecture.md"
if [ "$ARCH_RECORD" = approved ]; then
  if [ "${ARCH_GATE:-}" = approved ]; then
    { [ "${DELTA:-}" = applied ] && cat "$PRIOR_ARCH" 2>/dev/null; cat "$CURRENT_ARCH" 2>/dev/null; } > "$ARCH_FILE.tmp"
  else
    cat "$PRIOR_ARCH" 2>/dev/null > "$ARCH_FILE.tmp" \
      || { [ "${ARCH_GATE:-}" = carried ] && cat "$CURRENT_ARCH" 2>/dev/null > "$ARCH_FILE.tmp"; }
  fi
fi

REF_ROOT="refs/fresh-review/reviewed/$REVIEW_KEY"
printf 'update %s %s\nupdate %s %s\n' "$REF_ROOT/head" "$PR_HEAD" "$REF_ROOT/base" "$PR_MERGE_BASE" \
  | git update-ref --stdin 2>/dev/null || { rm -f "$RECORD.tmp" "$ARCH_FILE.tmp"; failed ref_update_failed; }
mv "$RECORD.tmp" "$RECORD" || { rm -f "$ARCH_FILE.tmp"; failed record_write_failed; }

if [ -s "$ARCH_FILE.tmp" ]; then
  mv "$ARCH_FILE.tmp" "$ARCH_FILE"
else
  rm -f "$ARCH_FILE.tmp"
  [ "$ARCH_RECORD" = approved ] || rm -f "$ARCH_FILE"
fi

printf '%s\n' "=== FRESH-REVIEW RECORD ===" "RECORD: written" \
  "KEY: $REVIEW_KEY" "HEAD: $PR_HEAD" "BLOCKERS: $COUNT" "=== END ==="
