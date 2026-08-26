#!/usr/bin/env bash
# fr-preflight.sh [--mode review|pr] [--pr <number|url>] — Step 1 + Step 2.
# Probes the repo, resolves the review scope, creates the run directory, and
# writes the state file every later script reads.
#
# --mode selects the output shape: `review` is findings only, `pr` adds the
# narrative pass. --pr implies --mode pr and additionally moves the subject of
# the review off the local branch, at which point scope resolution is finished by
# fr-pr-resolve.sh rather than here.
#
# Output contract (stdout): one block, keys only, no diff content.
#   === FRESH-REVIEW PREFLIGHT ===
#   STATUS: ok | stop
#   STOP_REASON: <slug>            (only when STATUS: stop)
#   RUN_DIR / STATE / MODE / PR_REF / BRANCH / DIRTY / AHEAD / BASE / DIFF_BASE
#   INDEX_TREE / HAS_GSTACK / HAS_CODEX / HAS_GH / CODEX_CFG / GSTACK_BIN
#   SOURCE_ROOT / REVIEW_SCOPE / DIFF_CMD
#   === END ===
#
# Exit 0 with STATUS: stop is a normal, expected outcome — the caller reads
# STOP_REASON and tells the user. A non-zero exit means the script itself broke.

set -u

emit() { printf '%s\n' "$1"; }

MODE=review
PR_REF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:?--mode needs a value}"; shift 2 ;;
    --pr)   PR_REF="${2:?--pr needs a value}"; MODE=pr; shift 2 ;;
    *)      echo "fr-preflight: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
case "$MODE" in
  review|pr) : ;;
  *) echo "fr-preflight: --mode must be review or pr, got '$MODE'" >&2; exit 2 ;;
esac

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  emit "=== FRESH-REVIEW PREFLIGHT ==="
  emit "STATUS: stop"
  emit "STOP_REASON: not_a_repo"
  emit "=== END ==="
  exit 0
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
BRANCH=$(git branch --show-current)
DIRTY=$(git status --porcelain | wc -l | tr -d ' ')
INDEX_TREE=$(git write-tree 2>/dev/null || echo "")

GSTACK_ROOT=""
for d in "$HOME/.claude/skills/gstack" "$HOME/.gstack/repos/gstack"; do
  [ -d "$d" ] && { GSTACK_ROOT="$d"; break; }
done
GSTACK_BIN="${GSTACK_ROOT:+$GSTACK_ROOT/bin}"

HAS_GSTACK=$([ -f "$HOME/.claude/skills/cso/SKILL.md" ] && echo 1 || echo 0)
HAS_CODEX=$(command -v codex >/dev/null 2>&1 && echo 1 || echo 0)
HAS_GH=$(command -v gh >/dev/null 2>&1 && echo 1 || echo 0)
CODEX_CFG=$([ -n "$GSTACK_BIN" ] && [ -x "$GSTACK_BIN/gstack-config" ] \
  && "$GSTACK_BIN/gstack-config" get codex_reviews 2>/dev/null || echo unknown)
[ -z "$CODEX_CFG" ] && CODEX_CFG=unknown

BASE=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
[ -z "$BASE" ] && BASE=main
git fetch origin "$BASE" --quiet 2>/dev/null || true
DIFF_BASE=$(git merge-base "origin/$BASE" HEAD 2>/dev/null || echo "")

if [ -n "$DIFF_BASE" ]; then
  AHEAD=$(git rev-list --count "$DIFF_BASE..HEAD")
else
  AHEAD=$(git rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo 0)
fi

# Both stop conditions are statements about the *local* tree, and with --pr the
# local tree is not the subject of the review: a clean checkout on main is the
# normal state from which you review someone else's PR, and a conflicted index
# never gets touched because this mode neither stages nor commits.
STOP_REASON=""
if [ -n "$PR_REF" ]; then
  :
elif [ -z "$INDEX_TREE" ]; then
  STOP_REASON="unmerged_index"
elif [ "$DIRTY" -eq 0 ] && [ "$AHEAD" -eq 0 ]; then
  STOP_REASON="nothing_to_review"
fi

if [ -n "$STOP_REASON" ]; then
  emit "=== FRESH-REVIEW PREFLIGHT ==="
  emit "STATUS: stop"
  emit "STOP_REASON: $STOP_REASON"
  emit "BRANCH: $BRANCH"
  emit "DIRTY: $DIRTY"
  emit "AHEAD: $AHEAD"
  emit "=== END ==="
  exit 0
fi

if [ -n "$DIFF_BASE" ]; then
  REVIEW_SCOPE="branch"
  DIFF_CMD="git diff $DIFF_BASE"
else
  REVIEW_SCOPE="working"
  DIFF_CMD="git diff HEAD"
fi

if grep -qx ".fresh-review/" "$REPO_ROOT/.gitignore" 2>/dev/null; then
  REPORT_DIR="$REPO_ROOT/.fresh-review"
else
  REPORT_DIR="$(git rev-parse --absolute-git-dir)/fresh-review"
fi
LOG_DIR="$(cd "$(git rev-parse --git-common-dir)" && pwd)/fresh-review"
# A --pr run names itself after the PR, not after whatever branch happened to be
# checked out — the local branch is incidental there and makes the run directory
# unfindable afterwards.
if [ -n "$PR_REF" ]; then
  RUN_SLUG="pr-$(printf '%s' "$PR_REF" | grep -oE '[0-9]+$' || echo ref)"
else
  RUN_SLUG="$(echo "$BRANCH" | tr '/' '-')"
fi
RUN_ID="$(date +%Y%m%d-%H%M%S)-$RUN_SLUG"
RUN_DIR="$REPORT_DIR/runs/$RUN_ID"
mkdir -p "$RUN_DIR/packet" "$RUN_DIR/raw" "$LOG_DIR"

STATE="$RUN_DIR/state.env"
# Every value is single-quote-escaped before it lands in state.env — a repo path
# or branch name containing a `'` would otherwise unbalance the quoting and break
# the `.` source in every later script. Same helper shape as fr-pr-resolve.sh's
# kv, but printing to stdout so the whole file is written in one truncating
# redirect rather than appended.
kv() { printf "%s='%s'\n" "$1" "$(printf '%s' "$2" | sed "s/'/'\\\\''/g")"; }
{
  kv REPO_ROOT "$REPO_ROOT"
  kv SOURCE_ROOT "$REPO_ROOT"
  kv MODE "$MODE"
  kv PR_REF "$PR_REF"
  kv RUN_ID "$RUN_ID"
  kv RUN_DIR "$RUN_DIR"
  kv REPORT_DIR "$REPORT_DIR"
  kv LOG_DIR "$LOG_DIR"
  kv BRANCH "$BRANCH"
  kv DIRTY "$DIRTY"
  kv AHEAD "$AHEAD"
  kv BASE "$BASE"
  kv DIFF_BASE "$DIFF_BASE"
  kv INDEX_TREE "$INDEX_TREE"
  kv GSTACK_BIN "$GSTACK_BIN"
  kv HAS_GSTACK "$HAS_GSTACK"
  kv HAS_CODEX "$HAS_CODEX"
  kv HAS_GH "$HAS_GH"
  kv CODEX_CFG "$CODEX_CFG"
  kv REVIEW_SCOPE "$REVIEW_SCOPE"
  kv DIFF_CMD "$DIFF_CMD"
  kv TS_START "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  kv T0 "$(date +%s)"
} > "$STATE"

emit "=== FRESH-REVIEW PREFLIGHT ==="
emit "STATUS: ok"
emit "RUN_DIR: $RUN_DIR"
emit "STATE: $STATE"
emit "MODE: $MODE"
emit "PR_REF: ${PR_REF:-none}"
emit "BRANCH: $BRANCH"
emit "DIRTY: $DIRTY"
emit "AHEAD: $AHEAD"
emit "BASE: $BASE"
emit "DIFF_BASE: ${DIFF_BASE:-none}"
emit "INDEX_TREE: $INDEX_TREE"
emit "HAS_GSTACK: $HAS_GSTACK"
emit "HAS_CODEX: $HAS_CODEX"
emit "HAS_GH: $HAS_GH"
emit "CODEX_CFG: $CODEX_CFG"
emit "GSTACK_BIN: ${GSTACK_BIN:-none}"
emit "SOURCE_ROOT: $REPO_ROOT"
emit "REVIEW_SCOPE: $REVIEW_SCOPE"
emit "DIFF_CMD: $DIFF_CMD"
emit "=== END ==="
