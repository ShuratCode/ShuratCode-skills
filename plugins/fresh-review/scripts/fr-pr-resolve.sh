#!/usr/bin/env bash
# fr-pr-resolve.sh <RUN_DIR> — Step 1.5, pr-remote mode only. Resolves the PR ref
# recorded by preflight into a reviewable local diff plus a source tree reviewers
# can actually open files from.
#
# Reads PR_REF from state.env. Bare number ("42") or a GitHub pull URL. Anything
# else is rejected rather than guessed at.
#
# Why a detached worktree and not just `gh pr diff`: reviewers are told to open a
# source file when the patch alone cannot settle whether something is a defect.
# With only a patch, those reads would hit the user's checkout — a different
# commit — and the reviewer would judge the PR against the wrong file contents.
# So the PR head is materialized once, and SOURCE_ROOT points every pass at it.
#
# The PR title is fetched but deliberately never enters the packet or any
# subagent prompt. It is the author's claim about the change; the narrative pass
# has to derive the change from the code, and a divergence between the two is a
# signal worth seeing rather than an input worth trusting.
#
# Output contract (stdout):
#   === FRESH-REVIEW PR RESOLVE ===
#   PR: resolved | unresolved
#   REASON: <slug>                   (only when unresolved)
#   PR_NUMBER / PR_URL / PR_STATE / PR_FORK / PR_HEAD / PR_BASE / HEAD_DRIFT
#   SOURCE_ROOT / REVIEW_SCOPE / DIFF_BASE / DIFF_CMD
#   === END ===
#
# Exit 0 with PR: unresolved is a normal outcome — the caller reports REASON and
# stops. There is no safe default to fall back to: silently reviewing the local
# branch instead would review the wrong change under the user's PR number.

set -u

RUN_DIR="${1:?usage: fr-pr-resolve.sh <RUN_DIR>}"
STATE="$RUN_DIR/state.env"
# shellcheck disable=SC1090
. "$STATE"

# Single-quote-escaped so a ref or URL containing a quote cannot corrupt
# state.env for every script that sources it afterwards.
kv() { printf "%s='%s'\n" "$1" "$(printf '%s' "$2" | sed "s/'/'\\\\''/g")" >> "$STATE"; }

unresolved() {
  printf '%s\n' "=== FRESH-REVIEW PR RESOLVE ===" \
    "PR: unresolved" \
    "REASON: $1" \
    "=== END ==="
  kv PR_RESOLVED "0"
  exit 0
}

command -v gh >/dev/null 2>&1 || unresolved "gh_missing"

case "$PR_REF" in
  '')                                    unresolved "no_pr_ref" ;;
  *[!0-9]*)
    case "$PR_REF" in
      *github.com/*/pull/*) : ;;
      *)                                 unresolved "bad_pr_ref" ;;
    esac
    ;;
esac

# A pull URL for a repo other than this checkout's origin has no tree here to
# build a worktree from, so it is refused rather than half-reviewed.
ORIGIN_SLUG=$(git remote get-url origin 2>/dev/null \
  | sed -E 's#^git@[^:]+:#/#; s#^[a-z+]+://[^/]+/#/#; s#\.git$##; s#^/##')
if [ -z "$ORIGIN_SLUG" ]; then
  unresolved "no_origin_remote"
fi
case "$PR_REF" in
  *github.com/*/pull/*)
    REF_SLUG=$(printf '%s' "$PR_REF" | sed -E 's#^.*github\.com[:/]+##; s#/pull/.*$##')
    if [ "$REF_SLUG" != "$ORIGIN_SLUG" ]; then
      unresolved "foreign_repo"
    fi
    ;;
esac

PR_JSON="$RUN_DIR/pr.json"
if ! gh pr view "$PR_REF" \
      --json number,title,url,state,isCrossRepository,headRefName,headRefOid,baseRefName \
      > "$PR_JSON" 2>"$RUN_DIR/raw/pr-view.err"; then
  unresolved "gh_pr_view_failed"
fi

read_field() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2],"") or "")' \
    "$PR_JSON" "$1" 2>/dev/null
}

PR_NUMBER=$(read_field number)
PR_URL=$(read_field url)
PR_STATE=$(read_field state)
PR_FORK=$(read_field isCrossRepository)
PR_HEAD_NAME=$(read_field headRefName)
PR_HEAD_OID=$(read_field headRefOid)
PR_BASE_NAME=$(read_field baseRefName)

[ -n "$PR_NUMBER" ] && [ -n "$PR_BASE_NAME" ] || unresolved "gh_pr_view_incomplete"

PR_LOCAL_REF="refs/fresh-review/pr-$PR_NUMBER"
if ! git fetch --quiet origin "pull/$PR_NUMBER/head:$PR_LOCAL_REF" --force \
      2>"$RUN_DIR/raw/pr-fetch.err"; then
  unresolved "pr_fetch_failed"
fi
PR_HEAD=$(git rev-parse "$PR_LOCAL_REF" 2>/dev/null) || unresolved "pr_head_missing"

# gh and the fetch are two round trips; a push in between is not an error, but
# the report has to name the commit that was actually reviewed.
HEAD_DRIFT=no
[ -n "$PR_HEAD_OID" ] && [ "$PR_HEAD_OID" != "$PR_HEAD" ] && HEAD_DRIFT=yes

git fetch --quiet origin "$PR_BASE_NAME" 2>/dev/null || true
DIFF_BASE=$(git merge-base "origin/$PR_BASE_NAME" "$PR_HEAD" 2>/dev/null || echo "")
[ -n "$DIFF_BASE" ] || unresolved "no_merge_base"

# In-repo only when preflight already established that path is gitignored —
# otherwise a nested worktree's files would show up as untracked dirt in the
# very diff under review. A worktree under the git dir is not an option.
case "$REPORT_DIR" in
  "$REPO_ROOT"/*) PR_WT="$REPORT_DIR/prwt-$RUN_ID" ;;
  *)              PR_WT="${TMPDIR:-/tmp}/fresh-review-prwt-$RUN_ID" ;;
esac
rm -rf "$PR_WT"
if ! git worktree add --quiet --detach "$PR_WT" "$PR_HEAD" 2>"$RUN_DIR/raw/pr-worktree.err"; then
  git worktree prune >/dev/null 2>&1 || true
  unresolved "worktree_failed"
fi

REVIEW_SCOPE="pr"
DIFF_CMD="git diff $DIFF_BASE $PR_HEAD"

# CHECKPOINT is set here because fr-checkpoint.sh does not run in this mode, and
# three later scripts branch on it. `pr_remote` is its own value rather than a
# reused `skipped` on purpose: skipped means "the tree was clean, so any dirt now
# is a reviewer's", which is false here — the user's own uncommitted work is
# untouched and still present. See fr-mutation-check.sh.
git status --porcelain > "$RUN_DIR/raw/pre-fanout.status"

{
  echo "CHECKPOINT='pr_remote'"
  echo "CHECKPOINT_SHA='$PR_HEAD'"
  echo "REVIEW_SCOPE='$REVIEW_SCOPE'"
  echo "DIFF_CMD='$DIFF_CMD'"
  echo "DIFF_BASE='$DIFF_BASE'"
  echo "SOURCE_ROOT='$PR_WT'"
  echo "PR_WT='$PR_WT'"
  echo "PR_LOCAL_REF='$PR_LOCAL_REF'"
  echo "PR_NUMBER='$PR_NUMBER'"
  echo "PR_HEAD='$PR_HEAD'"
  echo "PR_BASE_NAME='$PR_BASE_NAME'"
  echo "PR_FORK='$PR_FORK'"
  echo "HEAD_DRIFT='$HEAD_DRIFT'"
  echo "PR_RESOLVED='1'"
} >> "$STATE"
kv PR_URL "$PR_URL"
kv PR_STATE "$PR_STATE"

printf '%s\n' "=== FRESH-REVIEW PR RESOLVE ===" \
  "PR: resolved" \
  "PR_NUMBER: $PR_NUMBER" \
  "PR_URL: $PR_URL" \
  "PR_STATE: $PR_STATE" \
  "PR_FORK: $PR_FORK" \
  "PR_HEAD: $PR_HEAD" \
  "PR_BASE: $PR_BASE_NAME" \
  "HEAD_DRIFT: $HEAD_DRIFT" \
  "SOURCE_ROOT: $PR_WT" \
  "REVIEW_SCOPE: $REVIEW_SCOPE" \
  "DIFF_BASE: $DIFF_BASE" \
  "DIFF_CMD: $DIFF_CMD" \
  "=== END ==="
