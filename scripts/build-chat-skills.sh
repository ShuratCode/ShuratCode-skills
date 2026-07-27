#!/usr/bin/env bash
# build-chat-skills.sh — package each chat-skills/<skill> as an uploadable zip.
#
# claude.ai Chat has no marketplace: skills are uploaded one zip at a time via
# Customize > Skills > "+" > Create skill > Upload a skill.
#
# The zip must contain exactly ONE top-level folder whose name matches the
# skill's `name` frontmatter, with SKILL.md directly inside it.

set -euo pipefail
cd "$(dirname "$0")/.."

OUT="dist/chat-skills"
rm -rf "$OUT"
mkdir -p "$OUT"

command -v zip >/dev/null || { echo "zip is required" >&2; exit 1; }

shopt -s nullglob
found=0
for dir in chat-skills/*/; do
  name="$(basename "$dir")"
  [ -f "$dir/SKILL.md" ] || { echo "skip $name (no SKILL.md)" >&2; continue; }
  found=1

  # Zip from the parent so the archive contains "<name>/SKILL.md", not "SKILL.md".
  ( cd chat-skills && zip -q -r "../$OUT/$name.zip" "$name" -x '.*' -x '**/.*' )

  size=$(du -h "$OUT/$name.zip" | cut -f1 | tr -d ' ')
  root=$(unzip -Z1 "$OUT/$name.zip" | cut -d/ -f1 | sort -u | tr '\n' ' ')
  printf '  %-24s %6s   root: %s\n' "$name.zip" "$size" "$root"

  if [ "$(unzip -Z1 "$OUT/$name.zip" | cut -d/ -f1 | sort -u | wc -l | tr -d ' ')" != "1" ]; then
    echo "    ERROR: zip must have exactly one top-level folder" >&2
    exit 1
  fi
done

[ "$found" -eq 1 ] || { echo "no chat skills found" >&2; exit 1; }

echo
echo "Built into $OUT/"
echo "Upload at https://claude.ai/customize/skills — '+' > Create skill > Upload a skill."
