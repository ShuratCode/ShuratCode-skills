#!/usr/bin/env bash
# fr-mutation-check.sh <RUN_DIR> [--revert] — Step 6.5. Verifies mechanically that
# no reviewer subagent wrote to the tree.
#
# Detection is always safe to run. --revert is not, so the script refuses it under
# CHECKPOINT=failed: there the producer's own uncommitted work is interleaved with
# the reviewer's and `git restore` cannot tell them apart.
#
# Untracked files are only ever listed, never cleaned — `git clean` here could
# delete a file the user created seconds ago.
#
# Output contract (stdout):
#   === FRESH-REVIEW MUTATION CHECK ===
#   LEAK: none | detected
#   REVERT: n/a | done | refused_checkpoint_failed
#   PATHS: <one porcelain line per following line>  (only when LEAK: detected)
#   UNTRACKED_REMAINING: <paths>                    (only after REVERT: done)
#   === END ===

set -u

RUN_DIR="${1:?usage: fr-mutation-check.sh <RUN_DIR> [--revert]}"
DO_REVERT="${2:-}"
STATE="$RUN_DIR/state.env"
# shellcheck disable=SC1090
. "$STATE"

git status --porcelain > "$RUN_DIR/raw/post-fanout.status"

case "$CHECKPOINT" in
  committed|skipped)
    LEAK=$(cat "$RUN_DIR/raw/post-fanout.status")
    ;;
  failed)
    LEAK=$(diff "$RUN_DIR/raw/pre-fanout.status" "$RUN_DIR/raw/post-fanout.status" || true)
    ;;
  *)
    printf '%s\n' "=== FRESH-REVIEW MUTATION CHECK ===" \
      "LEAK: unknown" \
      "REVERT: refused_bad_state" \
      "PATHS: CHECKPOINT was '$CHECKPOINT' — expected committed|skipped|failed" \
      "=== END ==="
    exit 1
    ;;
esac

echo "=== FRESH-REVIEW MUTATION CHECK ==="

if [ -z "$LEAK" ]; then
  printf '%s\n' "LEAK: none" "REVERT: n/a" "=== END ==="
  exit 0
fi

echo "LEAK: detected"

if [ "$DO_REVERT" != "--revert" ]; then
  echo "REVERT: n/a"
elif [ "$CHECKPOINT" = "failed" ]; then
  echo "REVERT: refused_checkpoint_failed"
else
  mkdir -p "$RUN_DIR/quarantine"
  git diff HEAD > "$RUN_DIR/quarantine/reviewer-edits.patch"
  git restore --source=HEAD --worktree -- .
  echo "REVERT: done"
fi

echo "PATHS:"
printf '%s\n' "$LEAK"

if [ "$DO_REVERT" = "--revert" ] && [ "$CHECKPOINT" != "failed" ]; then
  echo "UNTRACKED_REMAINING:"
  git status --porcelain --untracked-files=all
fi

echo "=== END ==="
