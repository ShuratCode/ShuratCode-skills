#!/usr/bin/env bash
# fr-ui-detect.sh <RUN_DIR> — Step 4.6, pr mode only. Decides whether the
# orchestrator should attempt a best-effort UI screenshot of the change, and
# hands it everything it needs to try without ever reading the diff itself.
#
# Three independent gates, each a mechanical count or a file probe, all reduced
# to keys before printing so the orchestrator never sees diff content:
#
#   1. FRONTEND_HITS  — does the change touch UI code at all? (grep over files.txt)
#   2. LAUNCH_KIND    — is there a way to start the app without editing a tree
#                       under review? (a committed .claude/launch.json, or a
#                       dev/storybook script we may synthesize one from *only* in
#                       the disposable pr-remote worktree)
#   3. PR_HAS_IMAGE   — did the author already push a picture or mock? If so the
#                       reviewer does not need one generated. This is the ONE
#                       place the PR body is read, and it is read here — in a
#                       script that emits a boolean — precisely so the body never
#                       reaches Pass N, whose whole value is deriving the change
#                       from code alone. The body text is computed over and
#                       discarded; only the boolean is kept.
#
# UI_ELIGIBLE is yes only when a frontend change has a safe way to launch and the
# author supplied no image. Everything else prints UI_ELIGIBLE: no with a
# UI_REASON the orchestrator states out loud — a "not shown" line is information,
# not a silent skip.
#
# Output contract (stdout):
#   === FRESH-REVIEW UI DETECT ===
#   UI_ELIGIBLE / UI_REASON / FRONTEND_HITS / LAUNCH_KIND / LAUNCH_CMD
#   PR_HAS_IMAGE / ROUTES_HINT
#   === END ===

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
LAUNCH_KIND=none
LAUNCH_CMD=""
PR_HAS_IMAGE=unknown
ROUTES_HINT=""

emit() {
  kv UI_ELIGIBLE "$UI_ELIGIBLE"
  kv UI_REASON "$UI_REASON"
  kv FRONTEND_HITS "$FRONTEND_HITS"
  kv LAUNCH_KIND "$LAUNCH_KIND"
  kv LAUNCH_CMD "$LAUNCH_CMD"
  kv PR_HAS_IMAGE "$PR_HAS_IMAGE"
  kv ROUTES_HINT "$ROUTES_HINT"
  printf '%s\n' "=== FRESH-REVIEW UI DETECT ===" \
    "UI_ELIGIBLE: $UI_ELIGIBLE" \
    "UI_REASON: $UI_REASON" \
    "FRONTEND_HITS: $FRONTEND_HITS" \
    "LAUNCH_KIND: $LAUNCH_KIND" \
    "LAUNCH_CMD: $LAUNCH_CMD" \
    "PR_HAS_IMAGE: $PR_HAS_IMAGE" \
    "ROUTES_HINT: $ROUTES_HINT" \
    "=== END ==="
  exit 0
}

# pr mode is the only mode with a narrative reader; a UI preview belongs with it.
if [ "${MODE:-review}" != "pr" ]; then
  UI_REASON="not pr mode"
  emit
fi

# --- Gate 1: is this a frontend change at all? --------------------------------
# Component frameworks and stylesheets are unambiguous. Bare .ts/.js are not —
# they are as often backend — so they count only under a conventional UI dir.
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

# A short hint at which routes changed, so the orchestrator can navigate to them
# rather than only the app root. Pages/routes/screens dirs are the convention.
ROUTES_HINT=$(printf '%s\n' "$PATHS" \
  | grep -iE '(^|/)(pages|routes?|screens?|views?)(/|$)' \
  | grep -iE "$FRAMEWORK_RX" \
  | head -5 | paste -sd, - 2>/dev/null || true)

# --- Gate 3: did the author already push an image? ----------------------------
# Two ways an author supplies a picture: an image asset committed in the PR, or
# an image embedded in the PR description/comments. Check both. Only meaningful
# with a real PR (pr-remote); on your own branch there is no description to read,
# so treat it as "no image" and let gates 1 and 2 decide.
IMG_ASSET=$(printf '%s\n' "$PATHS" | grep -icE '\.(png|jpe?g|gif|webp|avif)$' || true)

if [ "$IMG_ASSET" -gt 0 ]; then
  PR_HAS_IMAGE=yes
elif [ "${PR_NUMBER:-}" != "" ] && [ "${HAS_GH:-0}" = "1" ]; then
  # Read body + comments, grep for an embedded image, discard the text. The
  # boolean is all that survives — the body must never reach a pass.
  BODYTEXT=$(gh pr view "$PR_NUMBER" --json body,comments \
    --jq '.body, (.comments[]?.body)' 2>/dev/null || true)
  if printf '%s' "$BODYTEXT" \
      | grep -qiE '!\[|<img|user-attachments|githubusercontent\.com/.*\.(png|jpe?g|gif|webp)|\.(png|jpe?g|gif|webp)([)"'"'"'?]|$)'; then
    PR_HAS_IMAGE=yes
  else
    PR_HAS_IMAGE=no
  fi
else
  # No PR to inspect (pr-local) — nobody pushed a description here.
  PR_HAS_IMAGE=no
fi

if [ "$PR_HAS_IMAGE" = "yes" ]; then
  UI_REASON="author already supplied an image"
  emit
fi

# --- Gate 2: can we launch without mutating a tree under review? --------------
SR="${SOURCE_ROOT:-$PWD}"
if [ -f "$SR/.claude/launch.json" ]; then
  LAUNCH_KIND=launch.json
  LAUNCH_CMD="preview_start (name from $SR/.claude/launch.json)"
else
  # A dev/storybook script is a launch recipe, but turning it into one needs a
  # .claude/launch.json written into the tree. That is safe ONLY in the
  # disposable pr-remote worktree (REVIEW_SCOPE=pr), which Step 9 deletes.
  # On your own checkout it would inject a file into the diff under review, so
  # we refuse and say why.
  PKG="$SR/package.json"
  if [ -f "$PKG" ]; then
    SCRIPT=$(python3 -c '
import json,sys
try: s=json.load(open(sys.argv[1])).get("scripts",{})
except Exception: s={}
for k in ("storybook","dev","start","serve","preview"):
    if k in s: print(k); break
' "$PKG" 2>/dev/null)
    if [ -n "$SCRIPT" ]; then
      if [ "${REVIEW_SCOPE:-}" = "pr" ]; then
        LAUNCH_KIND="script:$SCRIPT"
        LAUNCH_CMD="npm run $SCRIPT"
      else
        UI_REASON="a '$SCRIPT' script exists but no .claude/launch.json; synthesizing one would edit your checkout — add a launch.json to enable UI preview here"
        emit
      fi
    fi
  fi
fi

if [ "$LAUNCH_KIND" = "none" ]; then
  UI_REASON="no launch recipe (.claude/launch.json or a dev/storybook script) in ${SR}"
  emit
fi

UI_ELIGIBLE=yes
UI_REASON="frontend change, no author image, launchable via $LAUNCH_KIND"
emit
