#!/usr/bin/env bash
# test-ship-gate.sh — fixtures for fr-ship-gate.sh.
#
# The bug this exists to prevent: the gate selected its review-log entry by
# grepping the raw text for '"skill":"fresh-review"', but fr-handoff.sh writes
# the payload with json.dumps, which emits '"skill": "fresh-review"'. The grep
# never matched, so every run resolved to FR_GATE: none — indistinguishable from
# the legitimate "no recent run" answer, and the /ship trim was silently lost
# for the entire life of the feature.
#
# So the assertions below are on the resolved *tier*, never on "the script ran".
# A gate that always returns none passes any weaker check.
#
# Case 1 also pins a second trap: feeding the selector via `python3 - <<PY`
# instead of `python3 -c "$SCRIPT"` lets the heredoc claim stdin, the piped
# entries never arrive, and the gate returns none again.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/../scripts/fr-ship-gate.sh"
[ -f "$GATE" ] || { echo "cannot find fr-ship-gate.sh next to $HERE"; exit 2; }

PASS=0; FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME/.claude/skills/gstack/bin"
READER="$FAKE_HOME/.claude/skills/gstack/bin/gstack-review-read"
cat > "$READER" <<EOF
#!/usr/bin/env bash
cat "$TMP/entries.jsonl" 2>/dev/null || echo NO_REVIEWS
echo "---CONFIG---"
echo false
echo "---HEAD---"
EOF
chmod +x "$READER"

REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
SHA="$(git -C "$REPO" rev-parse HEAD)"

ts_ago() { python3 -c "
from datetime import datetime, timezone, timedelta
print((datetime.now(timezone.utc) - timedelta(hours=$1)).strftime('%Y-%m-%dT%H:%M:%SZ'))"; }
FRESH="$(ts_ago 2)"
STALE="$(ts_ago 30)"

# Built with json.dumps on purpose: this is the exact serializer fr-handoff.sh
# uses, so if its spacing ever changes these fixtures change with it.
entry() { python3 -c '
import json, sys
d = dict(p.split("=", 1) for p in sys.argv[1:])
if d.get("skip_passes"): d.pop("passes", None)
d.pop("skip_passes", None)
print(json.dumps(d))'  "$@"; }

fixture() { printf '%s\n' "$@" > "$TMP/entries.jsonl"; }

check() { # label field expected
  local label="$1" field="$2" want="$3" got
  got=$( (cd "$REPO" && HOME="$FAKE_HOME" bash "$GATE") | grep "^$field:" | head -1 | sed "s/^$field: *//")
  if [ "$got" = "$want" ]; then
    printf '  \033[32mok\033[0m    %s — %s: %s\n' "$label" "$field" "$got"
    PASS=$((PASS + 1))
  else
    printf '  \033[31mFAIL\033[0m  %s — %s: expected %s, got %s\n' "$label" "$field" "$want" "${got:-<empty>}"
    FAIL=$((FAIL + 1))
  fi
}

dirty()  { echo dirt > "$REPO/dirt.txt"; }
clean_() { rm -f "$REPO/dirt.txt"; }

printf '\n\033[1mfr-ship-gate.sh\033[0m\n'

# --- the regression: writer-format JSON must resolve to a real tier -----------
FR_OK=$(entry skill=fresh-review "timestamp=$FRESH" status=ok "commit=$SHA" \
              branch=main verdict=clean passes=lattice,cso,codex)

dirty
fixture "$FR_OK"
check "writer-format json, drifted tree" FR_GATE tier1
check "writer-format json, drifted tree" CUT_TESTING yes
check "writer-format json, drifted tree" CUT_CODEX_REVIEW yes
# tier1 keeps the adversarial pass: the tree moved since the review.
check "writer-format json, drifted tree" CUT_CODEX_ADVERSARIAL no

clean_
fixture "$FR_OK"
check "writer-format json, identical tree" FR_GATE tier2
check "writer-format json, identical tree" CUT_CODEX_ADVERSARIAL yes

# Selection must not depend on serializer spacing in either direction.
fixture "{\"skill\":\"fresh-review\",\"timestamp\":\"$FRESH\",\"commit\":\"$SHA\",\"passes\":\"lattice,cso,codex\"}"
check "compact json" FR_GATE tier2

# --- selection semantics ------------------------------------------------------
fixture "$(entry skill=review "timestamp=$FRESH" status=ok)" \
        "$(entry skill=cso "timestamp=$FRESH" status=ok)" \
        "$FR_OK"
check "other skills interleaved" FR_GATE tier2

fixture "$(entry skill=fresh-review "timestamp=$STALE" "commit=$SHA" passes=lattice)" "$FR_OK"
check "last fresh-review entry wins" FR_PASSES lattice,cso,codex

# --- cut derivation -----------------------------------------------------------
fixture "$(entry skill=fresh-review "timestamp=$FRESH" "commit=$SHA" passes=lattice)"
check "lattice pass only" CUT_TESTING yes
check "lattice pass only" CUT_CODEX_REVIEW no
check "lattice pass only" CUT_CODEX_ADVERSARIAL no

fixture "$(entry skill=fresh-review "timestamp=$FRESH" "commit=$SHA" passes=codex)"
check "codex pass only" CUT_TESTING no
check "codex pass only" CUT_CODEX_REVIEW yes

# --- every failure path must degrade to none ----------------------------------
fixture "$(entry skill=fresh-review "timestamp=$FRESH" \
           commit=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef passes=lattice,codex)"
check "checkpoint commit gone" FR_GATE tier1
check "checkpoint commit gone" FR_REASON checkpoint_commit_gone

fixture "$(entry skill=fresh-review "timestamp=$STALE" "commit=$SHA" passes=lattice)"
check "older than 24h" FR_GATE none
check "older than 24h" FR_REASON entry_older_than_24h

fixture "$(entry skill=fresh-review "timestamp=$FRESH" "commit=$SHA" skip_passes=1)"
check "entry without passes" FR_GATE none
check "entry without passes" FR_REASON entry_has_no_passes_field

fixture '{"skill": "fresh-review", broken'
check "corrupt entry line" FR_GATE none

fixture ""
check "empty log" FR_GATE none
check "empty log" FR_REASON no_fresh_review_entry

rm -f "$TMP/entries.jsonl"
check "reader returns NO_REVIEWS" FR_GATE none

chmod -x "$READER"
check "reader not executable" FR_REASON no_gstack_review_read
chmod +x "$READER"

# A gate that emitted a tier outside a repo would trim ship on unrelated trees.
got=$(cd "$TMP" && HOME="$FAKE_HOME" bash "$GATE" | grep '^FR_REASON:')
if [ "$got" = "FR_REASON: not_a_repo" ]; then
  printf '  \033[32mok\033[0m    outside a git repo — %s\n' "$got"; PASS=$((PASS + 1))
else
  printf '  \033[31mFAIL\033[0m  outside a git repo — expected not_a_repo, got %s\n' "$got"; FAIL=$((FAIL + 1))
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
