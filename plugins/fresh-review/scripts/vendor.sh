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
SRC_REFS="$PLUGIN_ROOT/skills/fresh-review/references"
SRC_SCRIPTS="$PLUGIN_ROOT/scripts"
MANIFEST="$PLUGIN_ROOT/.claude-plugin/plugin.json"

[ -f "$SRC_SKILL" ] || { echo "vendor: no source SKILL.md at $SRC_SKILL" >&2; exit 1; }
[ -f "$MANIFEST" ]  || { echo "vendor: no plugin.json at $MANIFEST" >&2; exit 1; }

VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$MANIFEST")"
SHA="$(git -C "$PLUGIN_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"

rm -rf "$TARGET/references"
mkdir -p "$TARGET/scripts" "$TARGET/references"

# 1. SKILL.md and references/*.md — drop the plugin-only Step 0 bootstrap block,
#    then rewrite every ${CLAUDE_PLUGIN_ROOT}/scripts/ and
#    ${CLAUDE_PLUGIN_ROOT}/skills/fresh-review/ reference so the vendored copy
#    resolves from the repo root with no CLAUDE_PLUGIN_ROOT. The bootstrap block
#    resolves CLAUDE_PLUGIN_ROOT for plugin installs; a vendored copy has no
#    plugin root (its refs become repo-root paths) and the block's bare
#    CLAUDE_PLUGIN_ROOT mentions would otherwise survive the rewrite, which only
#    touches those two prefixed forms. Prose mentions of ~/.claude/skills/...
#    (gstack/cso/ship) are left as-is: full-tier consumers have gstack.
REWRITES="$(python3 - "$SRC_SKILL" "$TARGET/SKILL.md" "$SRC_REFS" "$TARGET/references" <<'PY'
import pathlib, re, sys
src, dst, src_refs, dst_refs = sys.argv[1:5]
repo = '$(git rev-parse --show-toplevel)/.claude/skills/fresh-review/'
pairs = [('${CLAUDE_PLUGIN_ROOT}/scripts/', repo + 'scripts/'),
         ('${CLAUDE_PLUGIN_ROOT}/skills/fresh-review/', repo)]
def vendor(a, b):
    text = pathlib.Path(a).read_text()
    text = re.sub(r'\n*<!-- FR:BOOTSTRAP:START -->.*?<!-- FR:BOOTSTRAP:END -->\n*',
                  '\n\n', text, flags=re.DOTALL)
    n = 0
    for search, replace in pairs:
        n += text.count(search)
        text = text.replace(search, replace)
    pathlib.Path(b).write_text(text)
    return n
total = vendor(src, dst)
for ref in sorted(pathlib.Path(src_refs).glob("*.md")):
    total += vendor(ref, pathlib.Path(dst_refs) / ref.name)
print(total)
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
echo "  SKILL.md: $REWRITES plugin-root ref(s) rewritten to repo-root paths"
echo "  refs:     $(ls "$TARGET/references" | wc -l | tr -d ' ') references/*.md copied"
echo "  scripts:  $COUNT fr-*.sh copied (executable)"
echo "  stamp:    $TARGET/.fresh-review-version"
