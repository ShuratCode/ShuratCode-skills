#!/usr/bin/env bash
# fr-delta.sh <RUN_DIR> — Step 1.6, pr-remote only.
#
# Output contract (stdout):
#   === FRESH-REVIEW DELTA ===
#   DELTA: off | applied | full | none
#   DELTA_REASON: <slug>                        (full | none)
#   PRIOR_REVIEW: <run id> | none
#   PRIOR_HEAD / PRIOR_VERDICT / PRIOR_BLOCKERS / PRIOR_RISK (when a prior review exists)
#   DELTA_KIND: fast_forward | rebased          (applied)
#   DIFF_BASE / DIFF_CMD / DELTA_HEAD           (applied)
#   === END ===

set -u

RUN_DIR="${1:?usage: fr-delta.sh <RUN_DIR>}"
STATE="$RUN_DIR/state.env"
# shellcheck disable=SC1090
. "$STATE"

kv() { printf "%s='%s'\n" "$1" "$(printf '%s' "$2" | sed "s/'/'\\\\''/g")" >> "$STATE"; }

RECORD="$LOG_DIR/reviews/$REVIEW_KEY.json"
REF_ROOT="refs/fresh-review/reviewed/$REVIEW_KEY"
PRIOR_RUN=none
RECORD_STATE=missing

if [ -f "$RECORD" ]; then
  if FIELDS=$(python3 - "$RECORD" <<'PY'
import json, sys
record = json.load(open(sys.argv[1]))
required = ("severity", "file", "line", "category", "problem", "fix")
blockers = record.get("blockers")
if not record.get("run_id") or not isinstance(blockers, list):
    sys.exit(1)
if any(not isinstance(b, dict) or any(k not in b for k in required) for b in blockers):
    sys.exit(1)
for key in ("run_id", "verdict", "head", "base", "coverage", "risk"):
    print(record.get(key) or "-")
print(len(blockers))
PY
  ); then
    { read -r PRIOR_RUN; read -r PRIOR_VERDICT; read -r RECORD_HEAD; read -r RECORD_BASE
      read -r PRIOR_COVERAGE; read -r PRIOR_RISK; read -r PRIOR_BLOCKERS; } <<< "$FIELDS"
    RECORD_STATE=ok
  else
    RECORD_STATE=invalid
  fi
fi
PRIOR_HEAD=$(git rev-parse --verify -q "$REF_ROOT/head^{commit}" 2>/dev/null || echo "")
PRIOR_BASE=$(git rev-parse --verify -q "$REF_ROOT/base^{commit}" 2>/dev/null || echo "")

finish() {
  local delta="$1" reason="${2:-}"
  kv DELTA "$delta"
  kv DELTA_REASON "$reason"
  {
    echo "=== FRESH-REVIEW DELTA ==="
    echo "DELTA: $delta"
    [ -n "$reason" ] && echo "DELTA_REASON: $reason"
    echo "PRIOR_REVIEW: $PRIOR_RUN"
    if [ "$PRIOR_RUN" != none ]; then
      echo "PRIOR_HEAD: ${PRIOR_HEAD:-missing}"
      echo "PRIOR_VERDICT: $PRIOR_VERDICT"
      echo "PRIOR_BLOCKERS: $PRIOR_BLOCKERS"
      echo "PRIOR_RISK: $PRIOR_RISK"
    fi
    if [ "$delta" = applied ]; then
      echo "DELTA_KIND: $DELTA_KIND"
      echo "DIFF_BASE: $DELTA_BASE"
      echo "DIFF_CMD: $DIFF_CMD"
      echo "DELTA_HEAD: $DELTA_HEAD"
    fi
    echo "=== END ==="
  }
  exit 0
}

[ "${DELTA_REQUESTED:-0}" = 1 ] || finish off
[ "$RECORD_STATE" != missing ] || finish full no_prior_review
[ "$RECORD_STATE" = ok ] || finish full record_invalid
[ -n "$PRIOR_HEAD" ] && [ -n "$PRIOR_BASE" ] || finish full prior_head_missing
[ "$RECORD_HEAD" = "$PRIOR_HEAD" ] && [ "$RECORD_BASE" = "$PRIOR_BASE" ] || finish full record_mismatch
[ "$PRIOR_COVERAGE" = full ] || finish full prior_reduced_coverage
[ "$PRIOR_HEAD" != "$PR_HEAD" ] || [ "$PRIOR_BASE" != "$PR_MERGE_BASE" ] || finish none no_new_commits

MERGED=$(git merge-tree --write-tree --merge-base "$PRIOR_BASE" "$PR_MERGE_BASE" "$PRIOR_HEAD" \
  2>"$RUN_DIR/raw/delta-replay.err")
RC=$?
[ "$RC" -eq 1 ] && finish full replay_conflict
[ "$RC" -eq 0 ] || finish full replay_failed
REPLAYED_TREE=$(printf '%s\n' "$MERGED" | head -1)

if [ "$REPLAYED_TREE" = "$(git rev-parse "$PR_HEAD^{tree}")" ]; then
  [ "$PRIOR_BASE" = "$PR_MERGE_BASE" ] && finish none no_net_change
  [ "$PRIOR_BLOCKERS" -eq 0 ] || finish full rebased_with_blockers
  finish none rebase_only
fi

mkdir -p "$RUN_DIR/delta"
python3 - "$RECORD" "$RUN_DIR/delta/prior-blockers.md" <<'PY' || finish full record_invalid
import json, sys
record = json.load(open(sys.argv[1]))
lines = [f"# Blockers from the last review — run {record['run_id']}, "
         f"PR head {record['head']}, verdict {record['verdict']}", ""]
for i, b in enumerate(record["blockers"], 1):
    lines.append(f"B{i}. {b['severity']} {b['file']}:{b['line']} [{b['category']}] {b['problem']}")
    lines.append(f"    fix asked: {b['fix']}")
if not record["blockers"]:
    lines.append("none")
open(sys.argv[2], "w").write("\n".join(lines) + "\n")
PY

export GIT_AUTHOR_NAME=fresh-review GIT_AUTHOR_EMAIL=fresh-review@localhost
export GIT_COMMITTER_NAME=fresh-review GIT_COMMITTER_EMAIL=fresh-review@localhost
DELTA_BASE=$(git commit-tree --no-gpg-sign "$REPLAYED_TREE" -p "$PR_MERGE_BASE" \
  -m "fresh-review: PR as last reviewed at $PRIOR_HEAD, on its current base") || finish full replay_failed
DELTA_HEAD=$(git commit-tree --no-gpg-sign "$PR_HEAD^{tree}" -p "$DELTA_BASE" \
  -m "fresh-review: changes since the last review") || finish full replay_failed

git -c core.hooksPath=/dev/null -C "$PR_WT" checkout --quiet --detach "$DELTA_HEAD" \
  2>"$RUN_DIR/raw/delta-checkout.err" || finish full worktree_failed

DELTA_KIND=rebased
if [ "$PRIOR_BASE" = "$PR_MERGE_BASE" ] && git merge-base --is-ancestor "$PRIOR_HEAD" "$PR_HEAD"; then
  DELTA_KIND=fast_forward
fi
DIFF_CMD="git diff $DELTA_BASE $DELTA_HEAD"

kv DIFF_BASE "$DELTA_BASE"
kv DIFF_CMD "$DIFF_CMD"
kv DELTA_HEAD "$DELTA_HEAD"
kv DELTA_KIND "$DELTA_KIND"
kv DELTA_PRIOR_RUN "$PRIOR_RUN"
kv DELTA_PRIOR_HEAD "$PRIOR_HEAD"
kv DELTA_PRIOR_VERDICT "$PRIOR_VERDICT"
kv DELTA_PRIOR_BLOCKERS "$PRIOR_BLOCKERS"
kv DELTA_PRIOR_RISK "$PRIOR_RISK"
finish applied
