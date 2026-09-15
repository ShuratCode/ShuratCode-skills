#!/usr/bin/env bash
# test-ui-detect.sh — fixtures for fr-ui-detect.sh, Step 4.6's gate.
#
# The traps this exists to catch, in order of how quietly they fail:
#
# 1. Eligibility firing outside pr mode. A UI capture in the lean default run
#    would add latency to every pre-commit review that nobody asked for.
# 2. Synthesizing a launch.json into a tree under review. On your own branch
#    (REVIEW_SCOPE != pr) a bare dev script must be REFUSED, not turned into a
#    launch recipe — writing one injects a file into the very diff being reviewed.
# 3. Missing that the author already supplied an image. An image asset in the
#    diff (a committed mock) must set PR_HAS_IMAGE and make the change ineligible;
#    generating a screenshot on top of the author's own is wasted work.
# 4. Treating a bare .ts/.js as frontend. Backend TypeScript is not a UI change;
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
    echo "HAS_GH='0'"
    [ -n "${PR_NUMBER:-}" ] && echo "PR_NUMBER='$PR_NUMBER'"
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

# --- 3. frontend + launch.json --> eligible ----------------------------------
OUT="$(SETUP='mkdir -p "$run/src/.claude"; echo "{}" > "$run/src/.claude/launch.json"' \
       detect 'M\tapp/components/Nav.tsx\n')"
want "$OUT" UI_ELIGIBLE yes "frontend + committed launch.json"
want "$OUT" LAUNCH_KIND launch.json "frontend + committed launch.json"

# --- 4. pr-remote + dev script, no launch.json --> eligible (worktree is safe) -
OUT="$(SETUP='printf "{\"scripts\":{\"dev\":\"vite\"}}" > "$run/src/package.json"' \
       REVIEW_SCOPE=pr detect 'M\tsrc/pages/Checkout.tsx\n')"
want "$OUT" UI_ELIGIBLE yes "pr-remote dev script"
want "$OUT" LAUNCH_KIND "script:dev" "pr-remote dev script"

# --- 5. pr-local + dev script, no launch.json --> REFUSED (would edit checkout) -
OUT="$(SETUP='printf "{\"scripts\":{\"dev\":\"vite\"}}" > "$run/src/package.json"' \
       REVIEW_SCOPE=branch detect 'M\tsrc/pages/Checkout.tsx\n')"
want "$OUT" UI_ELIGIBLE no "pr-local dev script only"
case "$(key "$OUT" UI_REASON)" in
  *"would edit your checkout"*) ok "pr-local refusal names the mutation risk" ;;
  *) bad "pr-local refusal" "a 'would edit your checkout' reason" "$(key "$OUT" UI_REASON)" ;;
esac

# --- 6. image asset in the diff --> author already supplied a picture ---------
OUT="$(SETUP='mkdir -p "$run/src/.claude"; echo "{}" > "$run/src/.claude/launch.json"' \
       detect 'A\tsrc/pages/Login.tsx\nA\tdocs/mock-login.png\n')"
want "$OUT" PR_HAS_IMAGE yes "image asset committed"
want "$OUT" UI_ELIGIBLE no "image asset committed"

# --- 7. bare .ts under a non-UI dir is not a frontend hit ---------------------
OUT="$(detect 'M\tsrc/lib/parse.ts\n')"
want "$OUT" FRONTEND_HITS 0 "bare backend .ts"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
