#!/usr/bin/env bash

set -u

RUN_DIR="${1:?usage: fr-ui-images.sh <RUN_DIR>}"
STATE="$RUN_DIR/state.env"
# shellcheck disable=SC1090
. "$STATE"

BODY="$RUN_DIR/pr-context/body.md"
OUT_DIR="$RUN_DIR/ui/pr-images"
MAX="${FR_UI_MAX_IMAGES:-6}"
MAX_BYTES=10485760

kv() { printf "%s='%s'\n" "$1" "$(printf '%s' "$2" | sed "s/'/'\\\\''/g")" >> "$STATE"; }

FOUND=0; SKIPPED=0; FAILED=0
PATHS=()

emit() {
  kv UI_IMAGES "$FOUND"
  echo "=== FRESH-REVIEW UI IMAGES ==="
  echo "UI_IMAGES: $FOUND"
  local k=1
  for p in "${PATHS[@]+"${PATHS[@]}"}"; do
    echo "IMAGE_$k: $p"
    k=$((k + 1))
  done
  echo "UI_LINKS_SKIPPED: $SKIPPED"
  echo "UI_FETCH_FAILED: $FAILED"
  echo "=== END ==="
  exit 0
}

[ -f "$BODY" ] || emit

URLS=$( { grep -oE '!\[[^]]*\]\([^) ]+' "$BODY" | sed -E 's/^!\[[^]]*\]\(//'
          grep -oiE '<img[^>]+src=["'"'"']?[^"'"'"' >]+' "$BODY" | sed -E 's/.*[sS][rR][cC]=["'"'"']?//'
        } 2>/dev/null | awk '!seen[$0]++')

trusted() {
  case "$1" in
    https://github.com/user-attachments/assets/*) return 0 ;;
    https://user-images.githubusercontent.com/*) return 0 ;;
    https://private-user-images.githubusercontent.com/*) return 0 ;;
    https://github.com/*/*/assets/*) return 0 ;;
  esac
  return 1
}

TOKEN=""
[ "${HAS_GH:-0}" = 1 ] && TOKEN=$(gh auth token 2>/dev/null || true)

mkdir -p "$OUT_DIR"
while IFS= read -r url; do
  [ -n "$url" ] || continue
  if ! trusted "$url"; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi
  [ "$FOUND" -lt "$MAX" ] || break
  n=$((FOUND + FAILED + 1))
  tmp="$OUT_DIR/.fetch-$n"
  if [ -n "$TOKEN" ]; then
    curl -fsSL --proto '=https' --max-time 20 --max-filesize "$MAX_BYTES" \
      -H "Authorization: token $TOKEN" -o "$tmp" "$url" 2>/dev/null
  else
    curl -fsSL --proto '=https' --max-time 20 --max-filesize "$MAX_BYTES" -o "$tmp" "$url" 2>/dev/null
  fi || { rm -f "$tmp"; FAILED=$((FAILED + 1)); continue; }
  case "$(file -b --mime-type "$tmp" 2>/dev/null)" in
    image/png)  ext=png ;;
    image/jpeg) ext=jpg ;;
    image/gif)  ext=gif ;;
    image/webp) ext=webp ;;
    *) rm -f "$tmp"; FAILED=$((FAILED + 1)); continue ;;
  esac
  FOUND=$((FOUND + 1))
  mv "$tmp" "$OUT_DIR/$FOUND.$ext"
  PATHS+=("$OUT_DIR/$FOUND.$ext")
done <<< "$URLS"

emit
