#!/usr/bin/env bash
# test-vendor.sh — fixtures for vendor.sh, the generator that produces a pinned,
# vendored fresh-review skill for consumer repos.
#
# The whole point of vendoring is that the copy runs with NO ${CLAUDE_PLUGIN_ROOT}
# — a consumer has no plugin root. So the load-bearing assertion is that zero
# ${CLAUDE_PLUGIN_ROOT} survive in the output SKILL.md; a generator that copied
# the file verbatim would leave a skill that resolves none of its scripts. The
# rest pins the copy set (fr-*.sh only, never vendor.sh itself) and the version
# stamp used for drift detection.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VENDOR="$HERE/../scripts/vendor.sh"
MANIFEST="$HERE/../.claude-plugin/plugin.json"
[ -f "$VENDOR" ] || { echo "cannot find vendor.sh next to $HERE"; exit 2; }

command -v python3 >/dev/null || { echo "python3 required"; exit 2; }

PASS=0; FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()   { printf '  \033[32mok\033[0m    %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL + 1)); }
check() { # label condition-already-evaluated: pass "1"/"0"
  if [ "$2" = "1" ]; then ok "$1"; else bad "$1"; fi
}

printf '\n\033[1mvendor.sh\033[0m\n'

TARGET="$TMP/consumer/.claude/skills/fresh-review"
if OUT="$(bash "$VENDOR" "$TARGET" 2>&1)"; then
  ok "vendor.sh exits 0"
else
  bad "vendor.sh exits 0 — output: $OUT"
fi

SKILL="$TARGET/SKILL.md"

# 1. No ${CLAUDE_PLUGIN_ROOT} may survive — the consumer has no plugin root.
if [ -f "$SKILL" ]; then
  n=$(grep -c 'CLAUDE_PLUGIN_ROOT' "$SKILL" || true)
  check "zero \${CLAUDE_PLUGIN_ROOT} in output SKILL.md (found $n)" "$([ "$n" -eq 0 ] && echo 1 || echo 0)"
  # And the rewrite actually landed on the repo-root form.
  r=$(grep -c 'git rev-parse --show-toplevel)/.claude/skills/fresh-review/scripts/' "$SKILL" || true)
  check "script refs rewritten to repo-root form ($r found)" "$([ "$r" -gt 0 ] && echo 1 || echo 0)"
else
  bad "output SKILL.md exists"
  bad "script refs rewritten to repo-root form"
fi

# 2. Every fr-*.sh from the source is present in the output and executable.
SRC_SCRIPTS="$HERE/../scripts"
missing=0; nonexec=0; total=0
for f in "$SRC_SCRIPTS"/fr-*.sh; do
  [ -e "$f" ] || continue
  total=$((total + 1))
  b="$(basename "$f")"
  [ -f "$TARGET/scripts/$b" ] || { missing=$((missing + 1)); continue; }
  [ -x "$TARGET/scripts/$b" ] || nonexec=$((nonexec + 1))
done
check "all $total fr-*.sh present in output" "$([ "$missing" -eq 0 ] && echo 1 || echo 0)"
check "all fr-*.sh executable" "$([ "$nonexec" -eq 0 ] && echo 1 || echo 0)"

# 3. vendor.sh must never vendor itself, nor any non-fr-* script.
check "vendor.sh NOT copied into output" "$([ ! -e "$TARGET/scripts/vendor.sh" ] && echo 1 || echo 0)"
stray=$(find "$TARGET/scripts" -type f ! -name 'fr-*.sh' 2>/dev/null | wc -l | tr -d ' ')
check "only fr-*.sh in output scripts/ (stray: $stray)" "$([ "$stray" -eq 0 ] && echo 1 || echo 0)"

# 4. The pin/drift stamp is present and its version matches plugin.json.
STAMP="$TARGET/.fresh-review-version"
if [ -f "$STAMP" ]; then
  ok ".fresh-review-version present"
  want=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$MANIFEST")
  got=$(awk '{print $1}' "$STAMP")
  check "stamped version ($got) equals plugin.json ($want)" "$([ "$got" = "$want" ] && echo 1 || echo 0)"
else
  bad ".fresh-review-version present"
  bad "stamped version equals plugin.json"
fi

# 5. Idempotent — a second run over the same target overwrites cleanly and the
#    output is byte-identical.
before=$(cat "$SKILL" 2>/dev/null)
bash "$VENDOR" "$TARGET" >/dev/null 2>&1
after=$(cat "$SKILL" 2>/dev/null)
check "re-run overwrites cleanly (SKILL.md identical)" "$([ "$before" = "$after" ] && echo 1 || echo 0)"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
