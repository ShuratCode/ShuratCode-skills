#!/usr/bin/env bash
# fr-packet.sh <RUN_DIR> — Step 4. Materializes the shared diff packet once and
# classifies risk by pattern count.
#
# The orchestrator never sees diff content: everything below reduces the patch to
# integers before printing. Reviewers are handed the packet paths instead.
#
# Output contract (stdout):
#   === FRESH-REVIEW PACKET ===
#   FILES / LINES / INS / DEL / RISK / PATH_HITS / BODY_HITS / IAC_HITS
#   === END ===

set -u

RUN_DIR="${1:?usage: fr-packet.sh <RUN_DIR>}"
STATE="$RUN_DIR/state.env"
# shellcheck disable=SC1090
. "$STATE"

if [ "$REVIEW_SCOPE" = "working" ] && [ "$CHECKPOINT" = "committed" ]; then
  DIFF_CMD="git diff HEAD~1"
fi

# shellcheck disable=SC2086
$DIFF_CMD > "$RUN_DIR/packet/diff.patch"
# shellcheck disable=SC2086
$DIFF_CMD --stat > "$RUN_DIR/packet/stat.txt"
# shellcheck disable=SC2086
$DIFF_CMD --name-status > "$RUN_DIR/packet/files.txt"

FILE_COUNT=$(wc -l < "$RUN_DIR/packet/files.txt" | tr -d ' ')
# shellcheck disable=SC2086
SHORTSTAT=$($DIFF_CMD --shortstat)
INS=$(echo "$SHORTSTAT" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo 0)
DEL=$(echo "$SHORTSTAT" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo 0)
[ -z "$INS" ] && INS=0
[ -z "$DEL" ] && DEL=0

RX='auth|login|session|token|password|jwt|oauth|payment|billing|stripe|charge|refund|migration|schema|permission|authoriz|secret|credential|deserial'
PATH_HITS=$(grep -ciE "$RX" "$RUN_DIR/packet/files.txt" || true)
BODY_HITS=$(grep -ciE "$RX" "$RUN_DIR/packet/diff.patch" || true)
IAC_HITS=$(grep -ciE '\.github/workflows|Dockerfile|terraform|\.tf$|cdk|helm|k8s' "$RUN_DIR/packet/files.txt" || true)
LINES=$(grep -cE '^[+-]' "$RUN_DIR/packet/diff.patch" || true)

RISK=normal
if [ "$PATH_HITS" -gt 0 ] || [ "$IAC_HITS" -gt 0 ] || [ "$BODY_HITS" -gt 3 ] || [ "$LINES" -gt 300 ]; then
  RISK=high
fi

{
  echo "SCOPE=$REVIEW_SCOPE"
  echo "DIFF_CMD=$DIFF_CMD"
  echo "BASE=$BASE"
  echo "DIFF_BASE=$DIFF_BASE"
  echo "CHECKPOINT=$CHECKPOINT_SHA"
  echo "RISK=$RISK"
} > "$RUN_DIR/packet/scope.txt"

{
  echo "DIFF_CMD='$DIFF_CMD'"
  echo "FILE_COUNT='$FILE_COUNT'"
  echo "LINES='$LINES'"
  echo "INS='$INS'"
  echo "DEL='$DEL'"
  echo "RISK='$RISK'"
} >> "$STATE"

printf '%s\n' "=== FRESH-REVIEW PACKET ===" \
  "FILES: $FILE_COUNT" \
  "LINES: $LINES" \
  "INS: $INS" \
  "DEL: $DEL" \
  "RISK: $RISK" \
  "PATH_HITS: $PATH_HITS" \
  "BODY_HITS: $BODY_HITS" \
  "IAC_HITS: $IAC_HITS" \
  "=== END ==="
