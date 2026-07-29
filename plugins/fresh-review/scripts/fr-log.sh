#!/usr/bin/env bash
# fr-log.sh <RUN_DIR> — Step 10. Validates $RUN_DIR/run.json, appends it as one
# line to the durable index, prunes old run directories, and pings the gstack
# timeline.
#
# The skill writes run.json itself — only it knows the per-pass wall times, finding
# counts, and triage buckets. This script owns the parts that must not be done by
# hand: a malformed line appended to runs.jsonl breaks every future analysis of it,
# so validation gates the append rather than following it.
#
# Output contract (stdout):
#   === FRESH-REVIEW LOG ===
#   RUN_JSON: valid | invalid
#   APPENDED: yes | no
#   INDEX: <path>
#   PRUNED: <n>
#   === END ===

set -u

RUN_DIR="${1:?usage: fr-log.sh <RUN_DIR>}"
RETENTION="${FR_RUN_RETENTION:-20}"
STATE="$RUN_DIR/state.env"
# shellcheck disable=SC1090
. "$STATE"

echo "=== FRESH-REVIEW LOG ==="

if ONE_LINE=$(python3 -c 'import json,sys;print(json.dumps(json.load(open(sys.argv[1]))))' \
      "$RUN_DIR/run.json" 2>/dev/null); then
  echo "RUN_JSON: valid"
  printf '%s\n' "$ONE_LINE" >> "$LOG_DIR/runs.jsonl"
  echo "APPENDED: yes"
else
  echo "RUN_JSON: invalid"
  echo "APPENDED: no"
fi
echo "INDEX: $LOG_DIR/runs.jsonl"

PRUNED=0
if [ -d "$REPORT_DIR/runs" ]; then
  while IFS= read -r old; do
    [ -n "$old" ] || continue
    rm -rf "$old"
    PRUNED=$((PRUNED + 1))
  done < <(ls -1dt "$REPORT_DIR"/runs/*/ 2>/dev/null | tail -n +$((RETENTION + 1)))
fi
echo "PRUNED: $PRUNED"

if [ -n "$GSTACK_BIN" ] && [ -x "$GSTACK_BIN/gstack-timeline-log" ]; then
  T1=$(date +%s)
  "$GSTACK_BIN/gstack-timeline-log" \
    "{\"skill\":\"fresh-review\",\"event\":\"completed\",\"branch\":\"$BRANCH\",\"outcome\":\"${FR_STATUS:-unknown}\",\"duration_s\":\"$((T1 - T0))\"}" \
    >/dev/null 2>&1 || true
fi

echo "=== END ==="
