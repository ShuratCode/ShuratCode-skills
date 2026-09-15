#!/usr/bin/env bash
# test-ui-detect.sh — fixtures for fr-ui-detect.sh, Step 4.6's gate.
#
# fresh-review NEVER launches a review tree (launching was removed in v0.9.0
# because a review tree may be untrusted and provenance is not mechanically
# decidable). So UI_ELIGIBLE is always `no`; the script only classifies WHY.
#
# The traps this exists to catch, in order of how quietly they fail:
#
# 0. Ever launching a review tree. UI_ELIGIBLE must stay `no` even when a
#    committed .claude/launch.json is present, in EVERY scope — pr-remote AND a
#    locally-checked-out branch (REVIEW_SCOPE=branch). A `yes` here is the RCE
#    the feature was cut to prevent: the orchestrator would preview_start an
#    untrusted app on the reviewer's host.
# 1. Eligibility firing outside pr mode. UI context belongs with the narrative
#    reader; the lean default run must not carry it.
# 2. Treating a bare .ts/.js as frontend. Backend TypeScript is not a UI change;
#    only component frameworks, styles, or files under a UI dir count.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HERE/../scripts"
[ -f "$SCRIPTS/fr-ui-detect.sh" ] || { echo "cannot find fr-ui-detect.sh next to $HERE"; exit 2; }

PASS=0; FAIL=0
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

ok()  { printf '  ok   %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL %s\n       want %s / got %s\n' "$1" "$2" "$3"; FAIL=$((FAIL + 1)); }

key() { printf '%s\n' "$1" | grep "^$2:" | head -1 | sed "s/^$2: //"; }
want() { # output key expected label
  local got; got="$(key "$1" "$2")"
  [ "$got" = "$3" ] && ok "$4 — $2=$3" || bad "$4" "$2=$3" "$2=$got"
}

# Build a run dir with a state.env and a packet/files.txt (name-status format),
# plus an optional source-root layout, then run the detector and echo its stdout.
detect() { # name-status-lines | with state kv pairs after --
  local files="$1"; shift
  local run="$TMP/run"; rm -rf "$run"; mkdir -p "$run/packet" "$run/src"
  printf '%b' "$files" > "$run/packet/files.txt"
  {
    echo "MODE='${MODE:-pr}'"
    echo "REVIEW_SCOPE='${REVIEW_SCOPE:-pr}'"
    echo "SOURCE_ROOT='$run/src'"
  } > "$run/state.env"
  # optional filesystem setup callback
  [ -n "${SETUP:-}" ] && eval "$SETUP"
  bash "$SCRIPTS/fr-ui-detect.sh" "$run"
}

# --- 1. review mode is never eligible ----------------------------------------
OUT="$(MODE=review REVIEW_SCOPE=branch detect 'M\tapp/components/Nav.tsx\n')"
want "$OUT" UI_ELIGIBLE no "review mode"
want "$OUT" UI_REASON "not pr mode" "review mode"

# --- 2. no frontend files --> ineligible -------------------------------------
OUT="$(detect 'M\tsrc/api/orders.ts\nM\tREADME.md\n')"
want "$OUT" UI_ELIGIBLE no "backend-only change"
want "$OUT" FRONTEND_HITS 0 "backend-only change"

# --- 3. frontend change --> ineligible, launching removed --------------------
OUT="$(detect 'M\tapp/components/Nav.tsx\n')"
want "$OUT" UI_ELIGIBLE no "frontend change"
case "$(key "$OUT" UI_REASON)" in
  *"app launching removed"*) ok "frontend change names the launching-removed reason" ;;
  *) bad "frontend reason" "an 'app launching removed' reason" "$(key "$OUT" UI_REASON)" ;;
esac

# --- 4. RCE guard: a committed launch.json NEVER makes a tree eligible --------
# pr-remote (untrusted PR head) AND a locally-checked-out branch both hold this
# invariant. A `yes` here is the exact code-execution the feature was cut for.
for scope in pr branch; do
  OUT="$(SETUP='mkdir -p "$run/src/.claude"; echo "{}" > "$run/src/.claude/launch.json"' \
         REVIEW_SCOPE=$scope detect 'M\tsrc/pages/Checkout.tsx\n')"
  want "$OUT" UI_ELIGIBLE no "launch.json present, scope=$scope — never launched"
done

# --- 5. dev script present --> still never eligible ---------------------------
OUT="$(SETUP='printf "{\"scripts\":{\"dev\":\"vite\"}}" > "$run/src/package.json"' \
       REVIEW_SCOPE=branch detect 'M\tsrc/pages/Checkout.tsx\n')"
want "$OUT" UI_ELIGIBLE no "dev script present — never launched"

# --- 6. bare .ts under a non-UI dir is not a frontend hit --------------------
OUT="$(detect 'M\tsrc/lib/parse.ts\n')"
want "$OUT" FRONTEND_HITS 0 "bare backend .ts"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
