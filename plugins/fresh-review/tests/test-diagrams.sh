#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/fr-diagrams.sh"
[ -f "$SCRIPT" ] || { echo "cannot find fr-diagrams.sh next to $HERE"; exit 2; }

PASS=0; FAIL=0
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

ok()  { printf '  ok   %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL %s\n       want %s / got %s\n' "$1" "$2" "$3"; FAIL=$((FAIL + 1)); }

key() { printf '%s\n' "$1" | grep "^$2:" | head -1 | sed "s/^$2: //"; }
want() {
  local got; got="$(key "$1" "$2")"
  [ "$got" = "$3" ] && ok "$4 — $2=$3" || bad "$4" "$2=$3" "$2=$got"
}

FAKE_BIN="$TMP/fakebin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/bun" <<'EOF'
#!/usr/bin/env bash
[ "${FAKE_BUN:-ok}" = error ] && { echo "ERROR: render script did not finish: Parse error"; exit 1; }
[ "${FAKE_BUN:-ok}" = image ] && echo 'PAGE_ERRORS=["Error processing Mermaid diagram: x"]'
while [ $# -gt 0 ]; do
  [ "$1" = --out ] && { echo fake > "$2"; echo "OK $2"; shift; }
  shift
done
EOF
cat > "$FAKE_BIN/mmdc" <<'EOF'
#!/usr/bin/env bash
[ "${FAKE_MMDC:-ok}" = fail ] && exit 1
while [ $# -gt 0 ]; do
  [ "$1" = -o ] && { echo fake > "$2"; shift; }
  shift
done
EOF
chmod +x "$FAKE_BIN/bun" "$FAKE_BIN/mmdc"

GSTACK="$TMP/gstack"
mkdir -p "$GSTACK/bin" "$GSTACK/lib/diagram-render/dist"
echo '<html></html>' > "$GSTACK/lib/diagram-render/dist/diagram-render.html"
touch "$GSTACK/bin/gstack-render.ts"

mkrun() {
  local name="$1" gstack_bin="$2"; shift 2
  local run="$TMP/$name"
  mkdir -p "$run/ui"
  echo "GSTACK_BIN='$gstack_bin'" > "$run/state.env"
  for d in "$@"; do echo "graph LR; A-->B" > "$run/ui/$d.mmd"; done
  echo "$run"
}

run() { TMPDIR="$TMP" PATH="$FAKE_BIN:$PATH" "$@" bash "$SCRIPT" "$RUN"; }

echo "fr-diagrams.sh"

RUN=$(mkrun excalidraw "$GSTACK/bin" before after)
OUT=$(run env)
want "$OUT" RENDERER excalidraw "gstack present"
want "$OUT" DIAGRAM_before excalidraw "before renders with excalidraw"
want "$OUT" DIAGRAM_after excalidraw "after renders with excalidraw"
want "$OUT" PNG_after "$RUN/ui/after.png" "after png path reported"
want "$OUT" EDITABLE_before yes "clean render is editable"
want "$OUT" EXCALIDRAW_before "$RUN/ui/before.excalidraw" "excalidraw path reported"
[ -s "$RUN/ui/before.svg" ] && ok "svg written" || bad "svg written" "file" "missing"

RUN=$(mkrun old-names "$GSTACK/bin" class sequence flow)
OUT=$(run env)
want "$OUT" DIAGRAM_before none "old diagram names are not rendered"
[ -z "$(key "$OUT" DIAGRAM_class)" ] && ok "no class diagram line" || bad "no class diagram line" "" "$(key "$OUT" DIAGRAM_class)"

RUN=$(mkrun image-only "$GSTACK/bin" after)
OUT=$(run env FAKE_BUN=image)
want "$OUT" DIAGRAM_after mermaid "an image-only scene takes its png from mmdc"
want "$OUT" EDITABLE_after no "image-only scene is not editable"
want "$OUT" EXCALIDRAW_after "$RUN/ui/after.excalidraw" "the image-only scene is still linked"
want "$OUT" DIAGRAM_before none "missing source is none"

RUN=$(mkrun image-no-mmdc "$GSTACK/bin" after)
OUT=$(run env FAKE_BUN=image FAKE_MMDC=fail)
want "$OUT" DIAGRAM_after failed "an image-only scene with no mmdc never uses the raw mermaid raster"
want "$OUT" EXCALIDRAW_after "$RUN/ui/after.excalidraw" "the scene is linked even when no png renders"

RUN=$(mkrun parse-error "$GSTACK/bin" before)
OUT=$(run env FAKE_BUN=error)
want "$OUT" DIAGRAM_before mermaid "excalidraw error falls back to mmdc"
want "$OUT" PNG_before "$RUN/ui/before.png" "fallback png path reported"
[ -z "$(key "$OUT" EXCALIDRAW_before)" ] && ok "no excalidraw path on fallback" || bad "no excalidraw path on fallback" "" "$(key "$OUT" EXCALIDRAW_before)"

RUN=$(mkrun no-gstack "" before after)
OUT=$(run env)
want "$OUT" RENDERER mermaid "no gstack uses mermaid"
want "$OUT" DIAGRAM_before mermaid "before renders with mmdc"
want "$OUT" DIAGRAM_after mermaid "after renders with mmdc"

RUN=$(mkrun all-fail "$GSTACK/bin" after)
OUT=$(run env FAKE_BUN=error FAKE_MMDC=fail)
want "$OUT" DIAGRAM_after failed "both renderers fail"
[ -z "$(key "$OUT" PNG_after)" ] && ok "no png path on failure" || bad "no png path on failure" "" "$(key "$OUT" PNG_after)"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
