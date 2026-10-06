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

RUN=$(mkrun excalidraw "$GSTACK/bin" class sequence)
OUT=$(run env)
want "$OUT" RENDERER excalidraw "gstack present"
want "$OUT" DIAGRAM_class excalidraw "class renders with excalidraw"
want "$OUT" DIAGRAM_sequence excalidraw "sequence renders with excalidraw"
want "$OUT" EDITABLE_sequence yes "clean render is editable"
want "$OUT" EXCALIDRAW_class "$RUN/ui/class.excalidraw" "excalidraw path reported"
[ -s "$RUN/ui/class.svg" ] && ok "svg written" || bad "svg written" "file" "missing"

RUN=$(mkrun image-only "$GSTACK/bin" class)
OUT=$(run env FAKE_BUN=image)
want "$OUT" DIAGRAM_class excalidraw "image-only scene still counts"
want "$OUT" EDITABLE_class no "image-only scene is not editable"
want "$OUT" DIAGRAM_sequence none "missing source is none"

RUN=$(mkrun parse-error "$GSTACK/bin" class)
OUT=$(run env FAKE_BUN=error)
want "$OUT" DIAGRAM_class mermaid "excalidraw error falls back to mmdc"
want "$OUT" PNG_class "$RUN/ui/class.png" "fallback png path reported"
[ -z "$(key "$OUT" EXCALIDRAW_class)" ] && ok "no excalidraw path on fallback" || bad "no excalidraw path on fallback" "" "$(key "$OUT" EXCALIDRAW_class)"

RUN=$(mkrun no-gstack "" sequence)
OUT=$(run env)
want "$OUT" RENDERER mermaid "no gstack uses mermaid"
want "$OUT" DIAGRAM_sequence mermaid "sequence renders with mmdc"

RUN=$(mkrun all-fail "$GSTACK/bin" class)
OUT=$(run env FAKE_BUN=error FAKE_MMDC=fail)
want "$OUT" DIAGRAM_class failed "both renderers fail"
[ -z "$(key "$OUT" PNG_class)" ] && ok "no png path on failure" || bad "no png path on failure" "" "$(key "$OUT" PNG_class)"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
