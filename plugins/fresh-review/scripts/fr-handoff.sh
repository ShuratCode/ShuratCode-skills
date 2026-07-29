#!/usr/bin/env bash
# fr-handoff.sh <RUN_DIR> <status> <verdict> <passes-csv> <findings-json-file>
#
# Step 8.6. Writes this run into gstack's per-branch review log. That entry does
# two things downstream: ship's cross-review dedup suppresses findings logged as
# action:"skipped", and the ship-side dispatch gate
# (references/ship-dispatch-gate.md) reads it to decide which of ship's Step 9
# subagents are already covered.
#
# `passes` is the comma list of passes that returned STATUS: ok. The gate needs it:
# cutting ship's testing and maintainability specialists is only sound if the
# lattice pass actually ran, and cutting ship's Codex passes only if ours did.
#
# Must run BEFORE fr-restore.sh — it needs the checkpoint SHA the reset destroys.
#
# Output contract (stdout):
#   === FRESH-REVIEW HANDOFF ===
#   HANDOFF_RC: <n>
#   SHIP_GATE: armed | will_not_fire
#   REASON: <slug>                 (only when SHIP_GATE: will_not_fire)
#   === END ===

set -u

RUN_DIR="${1:?usage: fr-handoff.sh <RUN_DIR> <status> <verdict> <passes-csv> <findings-json-file>}"
STATUS="${2:?missing status}"
VERDICT="${3:?missing verdict}"
PASSES="${4:?missing passes csv}"
FINDINGS_FILE="${5:?missing findings json file}"
STATE="$RUN_DIR/state.env"
# shellcheck disable=SC1090
. "$STATE"

fail() { # rc  reason
  printf '%s\n' "=== FRESH-REVIEW HANDOFF ===" \
    "HANDOFF_RC: $1" \
    "SHIP_GATE: will_not_fire" \
    "REASON: $2" \
    "=== END ==="
  echo "HANDOFF_RC='$1'" >> "$STATE"
  exit 0
}

[ -f "$FINDINGS_FILE" ] || fail 2 "findings_file_missing"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$FINDINGS_FILE" 2>/dev/null \
  || fail 2 "findings_json_invalid"
[ -n "$GSTACK_BIN" ] && [ -x "$GSTACK_BIN/gstack-review-log" ] || fail 3 "no_gstack_install"

export FR_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export FR_STATUS="$STATUS"
export FR_COMMIT="$CHECKPOINT_SHA"
export FR_BRANCH="$BRANCH"
export FR_VERDICT="$VERDICT"
export FR_PASSES="$PASSES"

PAYLOAD=$(python3 - "$FINDINGS_FILE" <<'PY'
import json, os, sys
print(json.dumps({
    "skill": "fresh-review",
    "timestamp": os.environ["FR_TS"],
    "status": os.environ["FR_STATUS"],
    "commit": os.environ["FR_COMMIT"],
    "branch": os.environ["FR_BRANCH"],
    "verdict": os.environ["FR_VERDICT"],
    "passes": os.environ["FR_PASSES"],
    "findings": json.load(open(sys.argv[1])),
}))
PY
) || fail 2 "payload_build_failed"

printf '%s\n' "=== FRESH-REVIEW HANDOFF ==="
"$GSTACK_BIN/gstack-review-log" "$PAYLOAD" >/dev/null 2>&1
RC=$?
echo "HANDOFF_RC: $RC"
echo "HANDOFF_RC='$RC'" >> "$STATE"

if [ "$RC" -eq 0 ]; then
  echo "SHIP_GATE: armed"
else
  printf '%s\n' "SHIP_GATE: will_not_fire" "REASON: review_log_exit_$RC"
fi
echo "=== END ==="
