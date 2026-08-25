#!/usr/bin/env bash
# vendor.sh <target-skill-dir> — generate a pinned, vendored copy of the
# fresh-review skill into a consumer repo, e.g.
#   vendor.sh ~/activate/vi-activate/.claude/skills/fresh-review
#
# The Claude Desktop app cannot execute typed /plugin:command slash commands, so
# a team consumes fresh-review as a git-committed project skill living at
# <repo>/.claude/skills/fresh-review/. There is one maintained source (this
# plugin) and a generated, pinned copy per consumer. Re-running overwrites the
# vendored copy cleanly — that is how a consumer takes a new version.
set -euo pipefail

usage() { echo "usage: vendor.sh <target-skill-dir>" >&2; exit 2; }

TARGET="${1:-}"
[ -n "$TARGET" ] || usage

command -v python3 >/dev/null || { echo "vendor: python3 required" >&2; exit 2; }

# Resolve the plugin root from this script's own location so the generator runs
# from any cwd — including the marketplace cache.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_SKILL="$PLUGIN_ROOT/skills/fresh-review/SKILL.md"
SRC_SCRIPTS="$PLUGIN_ROOT/scripts"
MANIFEST="$PLUGIN_ROOT/.claude-plugin/plugin.json"

[ -f "$SRC_SKILL" ] || { echo "vendor: no source SKILL.md at $SRC_SKILL" >&2; exit 1; }
[ -f "$MANIFEST" ]  || { echo "vendor: no plugin.json at $MANIFEST" >&2; exit 1; }

VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$MANIFEST")"
SHA="$(git -C "$PLUGIN_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"

mkdir -p "$TARGET/scripts"

# 1. SKILL.md — rewrite every ${CLAUDE_PLUGIN_ROOT}/scripts/ reference so the
#    vendored scripts resolve from the repo root with no CLAUDE_PLUGIN_ROOT.
#    Prose mentions of ~/.claude/skills/... (gstack/cso/ship) are left as-is:
#    full-tier consumers have gstack.
REWRITES="$(python3 - "$SRC_SKILL" "$TARGET/SKILL.md" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
search = '${CLAUDE_PLUGIN_ROOT}/scripts/'
replace = '$(git rev-parse --show-toplevel)/.claude/skills/fresh-review/scripts/'
text = open(src).read()
print(text.count(search))
open(dst, "w").write(text.replace(search, replace))
PY
)"

# 2. fr-*.sh scripts — never vendor.sh, never non-fr-* scripts. Force the exec
#    bit so the vendored copies are runnable regardless of the source mode.
COUNT=0
for f in "$SRC_SCRIPTS"/fr-*.sh; do
  [ -e "$f" ] || continue
  cp "$f" "$TARGET/scripts/"
  chmod +x "$TARGET/scripts/$(basename "$f")"
  COUNT=$((COUNT + 1))
done

# 3. pin/drift stamp
printf '%s  %s\n' "$VERSION" "$SHA" > "$TARGET/.fresh-review-version"

echo "fresh-review vendored -> $TARGET"
echo "  version:  $VERSION  ($SHA)"
echo "  SKILL.md: $REWRITES script ref(s) rewritten to repo-root paths"
echo "  scripts:  $COUNT fr-*.sh copied (executable)"
echo "  stamp:    $TARGET/.fresh-review-version"
