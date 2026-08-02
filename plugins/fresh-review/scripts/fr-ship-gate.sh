#!/usr/bin/env bash
# fr-ship-gate.sh — resolves how much of /ship's Step 9 review army a recent
# fresh-review run already covers. Read-only; run from anywhere inside the repo.
#
# See references/ship-dispatch-gate.md for what each tier means and why each cut is
# sound. This script only resolves the tier and prints the cut list.
#
# Output contract (stdout):
#   === FRESH-REVIEW SHIP GATE ===
#   FR_GATE: none | tier1 | tier2
#   FR_REASON / FR_AGE_H / FR_DRIFT / FR_COMMIT / FR_PASSES
#   CUT_TESTING / CUT_MAINTAINABILITY / CUT_CODEX_REVIEW / CUT_CODEX_ADVERSARIAL: yes | no
#   === END ===
#
# Every failure path resolves to FR_GATE: none — no log, no gstack, unparseable
# entry, missing `passes` field. "No trim" is the only safe default: it costs
# duplicated work, while a wrong trim drops a lens from the final gate.

set -u

emit_none() { # reason
  printf '%s\n' "=== FRESH-REVIEW SHIP GATE ===" \
    "FR_GATE: none" \
    "FR_REASON: $1" \
    "CUT_TESTING: no" \
    "CUT_MAINTAINABILITY: no" \
    "CUT_CODEX_REVIEW: no" \
    "CUT_CODEX_ADVERSARIAL: no" \
    "=== END ==="
  exit 0
}

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || emit_none "not_a_repo"

READER="$HOME/.claude/skills/gstack/bin/gstack-review-read"
[ -x "$READER" ] || emit_none "no_gstack_review_read"

# The reader appends a ---CONFIG--- trailer after the entries; stop before it.
# Selection parses each line rather than grepping the raw text: fr-handoff.sh writes
# the entry with json.dumps defaults ('"skill": "fresh-review"'), so a text match on
# the compact spelling never fires and every resolution silently degrades to none.
# `python3 -c "$SELECT"`, not `python3 - <<PY`: the latter's heredoc claims stdin and
# the piped entries never arrive.
SELECT_LAST=$(cat <<'PY'
import json, sys

last = None
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        entry = json.loads(line)
    except Exception:
        continue
    if isinstance(entry, dict) and entry.get("skill") == "fresh-review":
        last = entry

if last is None:
    print("no - - -")
else:
    print("yes", last.get("timestamp") or "-", last.get("commit") or "-",
          last.get("passes") or "-")
PY
)

read -r FOUND TS COMMIT PASSES < <("$READER" 2>/dev/null | sed -n '/---CONFIG---/q;p' \
  | python3 -c "$SELECT_LAST")

[ "${FOUND:-no}" = "yes" ] || emit_none "no_fresh_review_entry"
[ "$TS" != "-" ] && [ -n "$TS" ] || emit_none "entry_has_no_timestamp"
[ "$PASSES" != "-" ] && [ -n "$PASSES" ] || emit_none "entry_has_no_passes_field"

AGE_H=$(python3 - "$TS" <<'PY'
import sys
from datetime import datetime, timezone
try:
    ts = datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00"))
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)
    print(f"{(datetime.now(timezone.utc) - ts).total_seconds() / 3600:.1f}")
except Exception:
    print("-")
PY
)

[ "$AGE_H" != "-" ] || emit_none "timestamp_unparseable"
python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) <= 24 else 1)' "$AGE_H" \
  || emit_none "entry_older_than_24h"

# git, never mtimes: `find -newermt` is unreliable here.
ALIVE=no
[ "$COMMIT" != "-" ] && git cat-file -e "${COMMIT}^{commit}" 2>/dev/null && ALIVE=yes

DRIFT=0
if [ "$ALIVE" = "yes" ]; then
  CHANGED=$(git diff --name-only "$COMMIT" HEAD 2>/dev/null | wc -l | tr -d ' ')
  UNCOMMITTED=$(git status --porcelain | wc -l | tr -d ' ')
  DRIFT=$((CHANGED + UNCOMMITTED))
fi

if [ "$ALIVE" != "yes" ]; then
  GATE=tier1; REASON="checkpoint_commit_gone"
elif [ "$DRIFT" -gt 0 ]; then
  GATE=tier1; REASON="tree_drifted_${DRIFT}_paths"
else
  GATE=tier2; REASON="fresh_and_identical_tree"
fi

case ",$PASSES," in *,lattice,*) HAS_LATTICE=yes ;; *) HAS_LATTICE=no ;; esac
case ",$PASSES," in *,codex,*) HAS_CODEX=yes ;; *) HAS_CODEX=no ;; esac

CUT_TESTING=$HAS_LATTICE
CUT_MAINTAINABILITY=$HAS_LATTICE
CUT_CODEX_REVIEW=$HAS_CODEX
CUT_CODEX_ADVERSARIAL=no
[ "$GATE" = "tier2" ] && CUT_CODEX_ADVERSARIAL=$HAS_CODEX

printf '%s\n' "=== FRESH-REVIEW SHIP GATE ===" \
  "FR_GATE: $GATE" \
  "FR_REASON: $REASON" \
  "FR_AGE_H: $AGE_H" \
  "FR_DRIFT: $DRIFT" \
  "FR_COMMIT: $COMMIT" \
  "FR_PASSES: $PASSES" \
  "CUT_TESTING: $CUT_TESTING" \
  "CUT_MAINTAINABILITY: $CUT_MAINTAINABILITY" \
  "CUT_CODEX_REVIEW: $CUT_CODEX_REVIEW" \
  "CUT_CODEX_ADVERSARIAL: $CUT_CODEX_ADVERSARIAL" \
  "=== END ==="
