#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/fr-ui-images.sh"
[ -f "$SCRIPT" ] || { echo "cannot find fr-ui-images.sh next to $HERE"; exit 2; }

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
printf '\x89PNG\r\n\x1a\n\0\0\0\rIHDR\0\0\0\x01\0\0\0\x01\x08\x06\0\0\0\x1f\x15\xc4\x89\0\0\0\nIDATx\x9cc\0\x01\0\0\x05\0\x01\r\n-\xb4\0\0\0\0IEND\xaeB`\x82' > "$TMP/pixel.png"
cat > "$FAKE_BIN/curl" <<EOF
#!/usr/bin/env bash
out=""; url=""; auth=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -o) out="\$2"; shift ;;
    -H) auth="\$2"; shift ;;
    --max-time|--max-filesize|--proto) shift ;;
    -*) ;;
    *) url="\$1" ;;
  esac
  shift
done
echo "\$url|\$auth" >> "$TMP/curl.log"
case "\$url" in
  *broken*) exit 22 ;;
  *notimage*) echo "<html>login</html>" > "\$out" ;;
  *) cp "$TMP/pixel.png" "\$out" ;;
esac
EOF
cat > "$FAKE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "auth token" ] && echo test-token
EOF
chmod +x "$FAKE_BIN/curl" "$FAKE_BIN/gh"

mkrun() {
  local name="$1" body="$2"
  local run="$TMP/$name"
  mkdir -p "$run"
  echo "HAS_GH='1'" > "$run/state.env"
  if [ -n "$body" ]; then
    mkdir -p "$run/pr-context"
    printf '%s\n' "$body" > "$run/pr-context/body.md"
  fi
  echo "$run"
}

run() { : > "$TMP/curl.log"; PATH="$FAKE_BIN:$PATH" "$@" bash "$SCRIPT" "$RUN"; }

echo "fr-ui-images.sh"

RUN=$(mkrun none "")
OUT=$(run env)
want "$OUT" UI_IMAGES 0 "no PR context"

RUN=$(mkrun mixed '## Screens
![before](https://github.com/user-attachments/assets/aaa)
<img width="400" src="https://private-user-images.githubusercontent.com/1/bbb.png?jwt=x">
![elsewhere](https://evil.example.com/track.png)
![again](https://github.com/user-attachments/assets/aaa)')
OUT=$(run env)
want "$OUT" UI_IMAGES 2 "markdown and html images on GitHub hosts"
want "$OUT" UI_LINKS_SKIPPED 1 "a link on another host is skipped"
want "$OUT" IMAGE_1 "$RUN/ui/pr-images/1.png" "image path reported"
[ -s "$RUN/ui/pr-images/2.png" ] && ok "second image saved" || bad "second image saved" "file" "missing"
grep -q "evil.example.com" "$TMP/curl.log" && bad "other host fetched" "never" "fetched" || ok "another host is never fetched"
[ "$(grep -c 'user-attachments/assets/aaa' "$TMP/curl.log")" = 1 ] && ok "a repeated link is fetched once" \
  || bad "repeated link" "1 fetch" "$(grep -c 'user-attachments/assets/aaa' "$TMP/curl.log")"
grep -q "|Authorization: token test-token$" "$TMP/curl.log" && ok "the gh token is sent to GitHub" \
  || bad "gh token" "Authorization header" "$(cat "$TMP/curl.log")"
grep -q "^UI_IMAGES='2'$" "$RUN/state.env" && ok "count written to state.env" || bad "state.env" "UI_IMAGES='2'" "$(cat "$RUN/state.env")"

RUN=$(mkrun bad 'x ![a](https://github.com/user-attachments/assets/notimage) ![b](https://github.com/user-attachments/assets/broken)')
OUT=$(run env)
want "$OUT" UI_IMAGES 0 "a non-image and a failed download"
want "$OUT" UI_FETCH_FAILED 2 "both counted as failed"
[ -z "$(ls -A "$RUN/ui/pr-images")" ] && ok "nothing left on disk" || bad "leftovers" "empty" "$(ls -A "$RUN/ui/pr-images")"

RUN=$(mkrun many "$(for i in 1 2 3 4; do echo "![s$i](https://github.com/user-attachments/assets/s$i)"; done)")
OUT=$(run env FR_UI_MAX_IMAGES=2)
want "$OUT" UI_IMAGES 2 "FR_UI_MAX_IMAGES caps the count"

RUN=$(mkrun nogh '![a](https://github.com/user-attachments/assets/a)')
echo "HAS_GH='0'" > "$RUN/state.env"
OUT=$(run env)
want "$OUT" UI_IMAGES 1 "no gh still fetches a public image"
grep -q "|$" "$TMP/curl.log" && ok "no token without gh" || bad "no token" "no header" "$(cat "$TMP/curl.log")"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
