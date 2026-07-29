#!/usr/bin/env bash
# fr-checkpoint.sh <RUN_DIR> — Step 3. Stages and commits a WIP checkpoint so
# untracked files land in the diff packet, or records that it was skipped.
#
# Sets CHECKPOINT to exactly one of: committed | skipped | failed. Never empty —
# three later steps branch on it and an unset value fails silently.
#
# Output contract (stdout):
#   === FRESH-REVIEW CHECKPOINT ===
#   CHECKPOINT: committed | skipped | failed
#   CHECKPOINT_SHA: <sha>
#   === END ===

set -u

RUN_DIR="${1:?usage: fr-checkpoint.sh <RUN_DIR>}"
STATE="$RUN_DIR/state.env"
# shellcheck disable=SC1090
. "$STATE"

if [ "$DIRTY" -eq 0 ]; then
  CHECKPOINT=skipped
else
  git add -A
  if git commit --no-verify -m "WIP: fresh-review checkpoint (will reset)" >/dev/null 2>&1; then
    CHECKPOINT=committed
  else
    CHECKPOINT=failed
    git status --porcelain > "$RUN_DIR/raw/pre-fanout.status"
  fi
fi
CHECKPOINT_SHA=$(git rev-parse HEAD)

{
  echo "CHECKPOINT='$CHECKPOINT'"
  echo "CHECKPOINT_SHA='$CHECKPOINT_SHA'"
} >> "$STATE"

printf '%s\n' "=== FRESH-REVIEW CHECKPOINT ===" \
  "CHECKPOINT: $CHECKPOINT" \
  "CHECKPOINT_SHA: $CHECKPOINT_SHA" \
  "=== END ==="
