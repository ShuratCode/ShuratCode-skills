#!/usr/bin/env bash
# fr-ui-detect.sh <RUN_DIR> — Step 4.6, pr mode only. Reports whether the diff
# touches frontend UI, so the orchestrator can print one honest line —
# `UI preview — not shown: <reason>`. It NEVER launches an app.
#
# fresh-review does not launch a review tree. A tree under review may hold
# untrusted code — a PR fetched with `--pr`, or a fork / dependabot branch you
# checked out locally to review — and whether the code is your own is NOT
# something that can be decided mechanically from the branch or the scope. So
# auto-launching any review tree is an arbitrary-code-execution risk on the
# reviewer's host (launch its `.claude/launch.json` or `dev` script and the
# author's code runs with your live credentials). Launching was removed in
# v0.9.0 rather than gated on a signal that cannot be trusted. To view the UI,
# open the branch yourself.
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

# pr mode is the only mode with a narrative reader; UI context belongs with it.
if [ "${MODE:-review}" != "pr" ]; then
  UI_REASON="not pr mode"
  emit
fi

# Does the change touch frontend UI at all? Component frameworks and stylesheets
# are unambiguous; bare .ts/.js are as often backend, so they count only under a
# conventional UI directory.
FRAMEWORK_RX='\.(tsx|jsx|vue|svelte|astro|mdx|css|scss|sass|less|styl|html)$'
UIDIR_RX='(^|/)(components?|pages|app|views?|screens?|routes?|ui|widgets?|layouts?|templates?|stories|public|assets/(css|scss|styles?))(/|$)'

# files.txt is `--name-status`: a status column, a tab, then the path (two paths
# on a rename). Reduce each line to its last field before matching.
PATHS=$(awk '{print $NF}' "$FILES" 2>/dev/null)

FRONTEND_HITS=$(printf '%s\n' "$PATHS" | grep -icE "$FRAMEWORK_RX" || true)
UIDIR_HITS=$(printf '%s\n' "$PATHS" | grep -icE "$UIDIR_RX" || true)
FRONTEND_HITS=$((FRONTEND_HITS > UIDIR_HITS ? FRONTEND_HITS : UIDIR_HITS))

if [ "$FRONTEND_HITS" -eq 0 ]; then
  UI_REASON="no frontend files in the diff"
  emit
fi

# Frontend changed — but fresh-review never launches a review tree (see the file
# header for why). Report it as an honest "not shown" so the reviewer opens the
# branch themselves. This holds for every scope, launch.json or not: a review
# tree is never auto-launched.
UI_REASON="app launching removed — fresh-review does not launch a review tree (${FRONTEND_HITS} frontend file(s) changed); open the branch yourself to view the UI"
emit
