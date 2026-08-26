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
#   RESET: done | skipped_not_committed | skipped_already_reset | failed
#   INDEX: restored | skipped_nothing_staged | skipped_no_tree | failed
#   WORKTREE: removed | skipped_none | failed        (pr-remote mode only)
#   === END ===
#
# Exits non-zero if any undo (RESET, INDEX, or WORKTREE) reported `failed`, so a
# scripted caller cannot mistake a failed restoration for a clean one.

set -u

RUN_DIR="${1:?usage: fr-restore.sh <RUN_DIR>}"
STATE="$RUN_DIR/state.env"
# shellcheck disable=SC1090
. "$STATE"

# Tolerate an incomplete state file. A run interrupted before fr-checkpoint.sh
# recorded CHECKPOINT still needs restoring — `git add -A` may already have run —
# and under `set -u` a bare `$CHECKPOINT` would abort here and strand the index.
# An empty CHECKPOINT is treated like `failed`: restore the index from the
# recorded INDEX_TREE, but never reset (that is gated on `committed` alone).
CHECKPOINT="${CHECKPOINT:-}"
CHECKPOINT_SHA="${CHECKPOINT_SHA:-}"
INDEX_TREE="${INDEX_TREE:-}"

RESET=skipped_not_committed
INDEX=skipped_nothing_staged
FAILED=0

if [ "$CHECKPOINT" = "committed" ]; then
  if [ "$(git rev-parse HEAD)" = "$CHECKPOINT_SHA" ]; then
    if git reset --soft HEAD~1; then
      RESET=done
    else
      RESET=failed
      FAILED=1
    fi
  else
    RESET=skipped_already_reset
  fi
fi

# committed and failed are exactly the two states where `git add -A` ran. An
# unrecorded (empty) CHECKPOINT means the run was interrupted before
# fr-checkpoint.sh persisted anything — restore the index only for a LOCAL run,
# where fr-checkpoint.sh (the sole stager) could have run. In a pr-remote run
# PR_REF is set and nothing of ours ever staged, so a read-tree there would
# silently discard whatever the user staged while the review was running — the
# same data-losing no-op the by-name gate exists to prevent.
RESTORE_INDEX=no
case "$CHECKPOINT" in
  committed|failed) RESTORE_INDEX=yes ;;
  "")               [ -z "${PR_REF:-}" ] && RESTORE_INDEX=yes ;;
esac

if [ "$RESTORE_INDEX" = yes ]; then
  if [ -n "$INDEX_TREE" ]; then
    if git read-tree "$INDEX_TREE"; then
      INDEX=restored
    else
      INDEX=failed
      FAILED=1
    fi
  else
    INDEX=skipped_no_tree
  fi
fi

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
  [ "$WORKTREE" = failed ] && FAILED=1
fi

echo "=== END ==="
git status --short

# A silent `RESET: done` / `INDEX: restored` over a git failure is exactly the
# data-loss this restore exists to prevent, so a failed undo is both reported in
# its field and signaled in the exit code for any scripted caller.
[ "$FAILED" -eq 0 ]
