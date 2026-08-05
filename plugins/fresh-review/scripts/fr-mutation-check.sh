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
#   REVERT: n/a | done | refused_checkpoint_failed | refused_pr_remote
#   PATHS: <one porcelain line per following line>  (only when LEAK: detected)
#   UNTRACKED_REMAINING: <paths>                    (only after REVERT: done)
#   PR_WT_LEAK: none | detected                     (only in pr-remote mode)
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
  failed|pr_remote)
    # Baseline diff, not raw status. Under pr_remote the user's own uncommitted
    # work was never staged or committed, so a raw status would report all of it
    # as a reviewer leak on the very first run.
    LEAK=$(diff "$RUN_DIR/raw/pre-fanout.status" "$RUN_DIR/raw/post-fanout.status" || true)
    ;;
  *)
    printf '%s\n' "=== FRESH-REVIEW MUTATION CHECK ===" \
      "LEAK: unknown" \
      "REVERT: refused_bad_state" \
      "PATHS: CHECKPOINT was '$CHECKPOINT' — expected committed|skipped|failed|pr_remote" \
      "=== END ==="
    exit 1
    ;;
esac

# The PR worktree is a second tree a reviewer could have written into, and it is
# the one they were pointed at. Its dirt counts as a leak even though it needs no
# revert — the worktree is deleted at restore, but a reviewer that ignored "do
# not fix" may also have ignored the forbidden-reads list.
PR_WT_LEAK=""
if [ -n "${PR_WT:-}" ] && [ -d "$PR_WT" ]; then
  PR_WT_LEAK=$(git -C "$PR_WT" status --porcelain)
  [ -n "$PR_WT_LEAK" ] && LEAK="$LEAK
$(printf '%s' "$PR_WT_LEAK" | sed "s#^#  [pr-worktree] #")"
fi

echo "=== FRESH-REVIEW MUTATION CHECK ==="

if [ -z "$LEAK" ]; then
  printf '%s\n' "LEAK: none" "REVERT: n/a"
  [ -n "${PR_WT:-}" ] && echo "PR_WT_LEAK: none"
  echo "=== END ==="
  exit 0
fi

echo "LEAK: detected"
[ -n "${PR_WT:-}" ] && echo "PR_WT_LEAK: $([ -n "$PR_WT_LEAK" ] && echo detected || echo none)"

if [ "$DO_REVERT" != "--revert" ]; then
  echo "REVERT: n/a"
elif [ "$CHECKPOINT" = "pr_remote" ]; then
  # Same reason as checkpoint_failed: nothing here was staged, so the user's own
  # uncommitted work is interleaved with any reviewer edit and `git restore`
  # cannot tell them apart. The PR worktree needs no revert — restore deletes it.
  echo "REVERT: refused_pr_remote"
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

if [ "$DO_REVERT" = "--revert" ] && [ "$CHECKPOINT" != "failed" ] && [ "$CHECKPOINT" != "pr_remote" ]; then
  echo "UNTRACKED_REMAINING:"
  git status --porcelain --untracked-files=all
fi

echo "=== END ==="
