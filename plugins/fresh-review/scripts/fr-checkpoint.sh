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

# Appended, not rewritten: state.env already holds INDEX_TREE from preflight, and
# `.`-sourcing takes the last assignment, so a pre-stage marker followed by the
# final value resolves correctly.
persist() { printf "CHECKPOINT='%s'\nCHECKPOINT_SHA='%s'\n" "$1" "$2" >> "$STATE"; }

if [ "$DIRTY" -eq 0 ]; then
  CHECKPOINT=skipped
  CHECKPOINT_SHA=$(git rev-parse HEAD)
  persist "$CHECKPOINT" "$CHECKPOINT_SHA"
else
  # Persist a pessimistic recovery marker BEFORE touching the index. `git add -A`
  # mutates the index whether or not the commit lands; if the run dies between the
  # two, state.env still carries CHECKPOINT='failed', so fr-restore.sh knows
  # staging happened and puts the index back from INDEX_TREE. Without it the
  # missing var aborts restore under `set -u` and the user's staging is lost.
  persist failed "$(git rev-parse HEAD)"
  git add -A
  if git commit --no-verify -m "WIP: fresh-review checkpoint (will reset)" >/dev/null 2>&1; then
    CHECKPOINT=committed
  else
    CHECKPOINT=failed
    git status --porcelain > "$RUN_DIR/raw/pre-fanout.status"
  fi
  CHECKPOINT_SHA=$(git rev-parse HEAD)
  persist "$CHECKPOINT" "$CHECKPOINT_SHA"
fi

printf '%s\n' "=== FRESH-REVIEW CHECKPOINT ===" \
  "CHECKPOINT: $CHECKPOINT" \
  "CHECKPOINT_SHA: $CHECKPOINT_SHA" \
  "=== END ==="
