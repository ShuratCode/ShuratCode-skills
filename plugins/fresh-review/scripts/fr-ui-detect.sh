#!/usr/bin/env bash
# fr-ui-detect.sh <RUN_DIR> — Step 4.6. Reports whether the diff touches
# frontend UI. It NEVER launches an app: the brief's screenshots come from the
# PR only (fr-ui-images.sh). See DESIGN.md, "Why the skill never runs the app".
#
# Output contract (stdout):
#   === FRESH-REVIEW UI DETECT ===
#   UI_ELIGIBLE / UI_REASON / FRONTEND_HITS
#   === END ===
#
# UI_ELIGIBLE is always `no` — the script produces a reason, never a launch.

set -u

RUN_DIR="${1:?usage: fr-ui-detect.sh <RUN_DIR>}"
STATE="$RUN_DIR/state.env"
# shellcheck disable=SC1090
. "$STATE"

kv() { printf "%s='%s'\n" "$1" "$(printf '%s' "$2" | sed "s/'/'\\\\''/g")" >> "$STATE"; }

FILES="$RUN_DIR/packet/files.txt"

UI_ELIGIBLE=no
UI_REASON=""
FRONTEND_HITS=0

emit() {
  kv UI_ELIGIBLE "$UI_ELIGIBLE"
  kv UI_REASON "$UI_REASON"
  kv FRONTEND_HITS "$FRONTEND_HITS"
  printf '%s\n' "=== FRESH-REVIEW UI DETECT ===" \
    "UI_ELIGIBLE: $UI_ELIGIBLE" \
    "UI_REASON: $UI_REASON" \
    "FRONTEND_HITS: $FRONTEND_HITS" \
    "=== END ==="
  exit 0
}

# Component frameworks and stylesheets are unambiguous; bare .ts/.js are as
# often backend, so they count only under a conventional UI directory.
FRAMEWORK_RX='\.(tsx|jsx|vue|svelte|astro|mdx|css|scss|sass|less|styl|html)$'
UIDIR_RX='(^|/)(components?|pages|app|views?|screens?|routes?|ui|widgets?|layouts?|templates?|stories|public|assets/(css|scss|styles?))(/|$)'

# files.txt is `--name-status`: reduce each line to its last field (the new path
# on a rename) before matching.
PATHS=$(awk '{print $NF}' "$FILES" 2>/dev/null)

FRONTEND_HITS=$(printf '%s\n' "$PATHS" | grep -icE "$FRAMEWORK_RX" || true)
UIDIR_HITS=$(printf '%s\n' "$PATHS" | grep -icE "$UIDIR_RX" || true)
FRONTEND_HITS=$((FRONTEND_HITS > UIDIR_HITS ? FRONTEND_HITS : UIDIR_HITS))

if [ "$FRONTEND_HITS" -eq 0 ]; then
  UI_REASON="no frontend files in the diff"
  emit
fi

UI_REASON="${FRONTEND_HITS} frontend file(s) changed — screenshots come from the PR only; the app is never launched"
emit
