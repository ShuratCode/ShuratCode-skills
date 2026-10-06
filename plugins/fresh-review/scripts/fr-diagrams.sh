#!/usr/bin/env bash
set -u

RUN_DIR="${1:?usage: fr-diagrams.sh <RUN_DIR>}"
UI="$RUN_DIR/ui"
# shellcheck disable=SC1090
[ -f "$RUN_DIR/state.env" ] && . "$RUN_DIR/state.env"

GSTACK_ROOT="${GSTACK_BIN:+${GSTACK_BIN%/bin}}"
BUNDLE="$GSTACK_ROOT/lib/diagram-render/dist/diagram-render.html"
RENDER="$GSTACK_ROOT/bin/gstack-render.ts"
STAGED=""

stage_bundle() {
  [ -n "$GSTACK_ROOT" ] && [ -f "$BUNDLE" ] && [ -f "$RENDER" ] && command -v bun >/dev/null 2>&1 || return 1
  local rd="${TMPDIR:-/tmp}/gstack-render" sha
  if [ -e "$rd" ] && { [ -L "$rd" ] || [ ! -O "$rd" ]; }; then
    rd=$(mktemp -d "${TMPDIR:-/tmp}/gstack-render.XXXXXX")
  else
    mkdir -p -m 700 "$rd"
  fi
  sha=$(shasum -a 256 "$BUNDLE" | cut -c1-16)
  STAGED="$rd/gstack-diagram-render-$sha.html"
  { [ -f "$STAGED" ] && shasum -a 256 "$STAGED" | grep -q "^$sha"; } \
    || { cp "$BUNDLE" "$STAGED.$$" && mv "$STAGED.$$" "$STAGED"; }
}

render_excalidraw() {
  local d="$1" src out
  [ -n "$STAGED" ] || return 1
  src=$(base64 < "$UI/$d.mmd" | tr -d '\n')
  out=$(bun run "$RENDER" "$STAGED" --wait-selector '#done' \
    --eval "window.__renderMermaid('$d', decodeURIComponent(escape(atob('$src')))).then(s => (window.__svg = s))" --out "$UI/$d.svg" \
    --eval "window.__rasterize(window.__svg, 1950)" --out "$UI/$d.png" \
    --eval "window.__mermaidToExcalidraw(decodeURIComponent(escape(atob('$src')))).then(j => (window.__scene = j))" --out "$UI/$d.excalidraw" 2>&1)
  printf '%s\n' "$out" > "$UI/$d.render.log"
  printf '%s\n' "$out" | grep -q '^ERROR' && return 1
  [ -s "$UI/$d.png" ] && [ -s "$UI/$d.excalidraw" ]
}

render_mermaid() {
  local d="$1"
  command -v mmdc >/dev/null 2>&1 || return 1
  mmdc -i "$UI/$d.mmd" -o "$UI/$d.png" > "$UI/$d.mmdc.log" 2>&1 && [ -s "$UI/$d.png" ]
}

editable() {
  grep -q 'Error processing Mermaid diagram' "$UI/$1.render.log" 2>/dev/null && echo no || echo yes
}

stage_bundle || STAGED=""

echo "=== FRESH-REVIEW DIAGRAMS ==="
echo "RENDERER: $([ -n "$STAGED" ] && echo excalidraw || echo mermaid)"
for d in class sequence; do
  if [ ! -f "$UI/$d.mmd" ]; then
    echo "DIAGRAM_$d: none"
    continue
  fi
  rm -f "$UI/$d.png" "$UI/$d.svg" "$UI/$d.excalidraw"
  if render_excalidraw "$d"; then
    echo "DIAGRAM_$d: excalidraw"
    echo "PNG_$d: $UI/$d.png"
    echo "EXCALIDRAW_$d: $UI/$d.excalidraw"
    echo "EDITABLE_$d: $(editable "$d")"
  elif render_mermaid "$d"; then
    echo "DIAGRAM_$d: mermaid"
    echo "PNG_$d: $UI/$d.png"
  else
    echo "DIAGRAM_$d: failed"
  fi
done
echo "=== END ==="
