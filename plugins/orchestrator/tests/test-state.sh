#!/usr/bin/env bash

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
STATE="$HERE/../scripts/orc-state.sh"
PASS=0; FAIL=0
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export ORC_STATE_DIR="$TMP/state"

ok()  { printf '  ok   %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL %s\n       want %s / got %s\n' "$1" "$2" "$3"; FAIL=$((FAIL + 1)); }
key() { printf '%s\n' "$1" | grep "^$2:" | head -1 | sed "s/^$2: *//"; }
want() {
  local got; got="$(key "$1" "$2")"
  [ "$got" = "$3" ] && ok "$4 — $2=$3" || bad "$4" "$2=$3" "$2=$got"
}
has() { printf '%s\n' "$1" | grep -qF -- "$2" && ok "$3" || bad "$3" "'$2'" "$1"; }
S() { bash "$STATE" "$@"; }

echo "init"
want "$(S init R-1 feature)" STATUS ok "feature track"
T="$(S table R-1)"
has "$T" "| SPEC | — | not started | — | — |" "spec row starts empty"
has "$T" "| SHIP |" "ship row present"
want "$(S init R-1 feature)" REASON state_exists "no silent overwrite"
want "$(S init R-1 bug --force)" STATUS ok "force re-init"
has "$(S table R-1)" "| BUILD |" "bug track starts at build"
printf '%s\n' "$(S table R-1)" | grep -q "SPEC" && bad "bug track has no spec" "no SPEC" "SPEC" || ok "bug track has no spec"
want "$(S init R-2 sideways)" REASON bad_track "unknown track"
want "$(S init '../x' feature)" REASON bad_ticket "path-like ticket refused"

echo "set"
S init R-3 fast > /dev/null
want "$(S set R-3 build session=local_abc name=r3-build status=running)" STATUS ok "set fields"
has "$(S table R-3)" "| BUILD | [r3-build](#local_abc) | running | — | — |" "session link in table"
want "$(S set R-3 build status=finished)" REASON bad_status "unknown status"
want "$(S set R-3 build owner=me)" REASON bad_key "unknown key"
want "$(S set R-3 spec status=done)" REASON no_such_stage "stage not in track"
S set R-3 review status=blocked "needs=approve | merge" > /dev/null
has "$(S table R-3)" 'approve \| merge' "pipe escaped in table"

echo "nudge once, then stop"
want "$(S nudge R-3 build)" NUDGE allowed "first miss nudges"
has "$(S table R-3)" "unmet (nudged)" "nudge recorded"
want "$(S nudge R-3 build)" NUDGE refused "second miss stops"
has "$(S table R-3)" "| BUILD | [r3-build](#local_abc) | stopped | unmet (stopped) |" "stage stopped"
want "$(S nudge R-3 build)" NUDGE refused "never a third nudge"

echo "state survives a new shell"
has "$(bash -c "ORC_STATE_DIR='$ORC_STATE_DIR' bash '$STATE' table R-3")" "unmet (stopped)" "read back from disk"

echo "default dir is the git common dir"
mkdir -p "$TMP/repo" && git -C "$TMP/repo" init -q
P="$(cd "$TMP/repo" && ORC_STATE_DIR= bash "$STATE" path R-9)"
[ "$P" = "$TMP/repo/.git/orchestrator/R-9.tsv" ] && ok "state under .git/orchestrator" || bad "state path" "$TMP/repo/.git/orchestrator/R-9.tsv" "$P"
want "$(cd "$TMP" && ORC_STATE_DIR= bash "$STATE" path R-9)" REASON not_a_repo "outside a repo"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
