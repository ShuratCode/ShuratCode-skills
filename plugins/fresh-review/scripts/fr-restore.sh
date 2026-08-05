#!/usr/bin/env bash
# fr-restore.sh <RUN_DIR> — Step 9. Three independent undos, each separately gated.
#
#   1. drop the checkpoint commit    — only when it actually landed
#   2. restore the pre-review index  — whenever `git add -A` ran, including on
#                                      CHECKPOINT=failed
#   3. tear down the PR worktree     — pr-remote mode only
#
# `git read-tree` restores the exact staged content, so a partially staged file
# comes back split as the user had it. Re-staging by filename would flatten it.
#
# Idempotent: safe to run again after an interrupted run. Once the reset has
# happened, HEAD is no longer the checkpoint commit, so it is not repeated.
#
# Output contract (stdout):
#   === FRESH-REVIEW RESTORE ===
#   RESET: done | skipped_not_committed | skipped_already_reset
#   INDEX: restored | skipped_nothing_staged | skipped_no_tree
#   WORKTREE: removed | skipped_none | failed        (pr-remote mode only)
#   === END ===

set -u

RUN_DIR="${1:?usage: fr-restore.sh <RUN_DIR>}"
STATE="$RUN_DIR/state.env"
# shellcheck disable=SC1090
. "$STATE"

RESET=skipped_not_committed
INDEX=skipped_nothing_staged

if [ "$CHECKPOINT" = "committed" ]; then
  if [ "$(git rev-parse HEAD)" = "$CHECKPOINT_SHA" ]; then
    git reset --soft HEAD~1
    RESET=done
  else
    RESET=skipped_already_reset
  fi
fi

# Named states rather than `!= skipped`: committed and failed are exactly the two
# where `git add -A` ran. pr_remote never staged anything, and read-tree there
# would silently discard anything the user staged while the review was running.
case "$CHECKPOINT" in
  committed|failed)
    if [ -n "$INDEX_TREE" ]; then
      git read-tree "$INDEX_TREE"
      INDEX=restored
    else
      INDEX=skipped_no_tree
    fi
    ;;
esac

printf '%s\n' "=== FRESH-REVIEW RESTORE ===" \
  "RESET: $RESET" \
  "INDEX: $INDEX"

if [ -n "${PR_WT:-}" ]; then
  WORKTREE=skipped_none
  if [ -d "$PR_WT" ]; then
    if git worktree remove --force "$PR_WT" 2>/dev/null; then
      WORKTREE=removed
    else
      rm -rf "$PR_WT"
      WORKTREE=$([ -d "$PR_WT" ] && echo failed || echo removed)
    fi
  fi
  git worktree prune >/dev/null 2>&1 || true
  [ -n "${PR_LOCAL_REF:-}" ] && git update-ref -d "$PR_LOCAL_REF" 2>/dev/null
  echo "WORKTREE: $WORKTREE"
fi

echo "=== END ==="
git status --short
