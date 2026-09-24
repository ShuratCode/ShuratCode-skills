#!/usr/bin/env bash

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HERE/../scripts"
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

gate() {
  local dir="$TMP/run-$1"; mkdir -p "$dir"
  printf '%s\n' "${@:2}" > "$dir/state.env"
  bash "$SCRIPTS/fr-arch-gate.sh" "$dir"
}

printf '\n\033[1mfresh-review architecture gate\033[0m\n'

OUT="$(gate undecided "ARCH_APPROVED='0'")"
want "$OUT" ARCH_GATE closed "no gate outcome recorded"
want "$OUT" REASON not_decided "no gate outcome recorded"

OUT="$(gate pending "ARCH_APPROVED='0'" "ARCH_GATE='pending'")"
want "$OUT" ARCH_GATE closed "gate pending"

OUT="$(gate rejected "ARCH_APPROVED='0'" "ARCH_GATE='rejected'")"
want "$OUT" ARCH_GATE closed "gate rejected"

OUT="$(gate bogus "ARCH_APPROVED='0'" "ARCH_GATE='yes please'")"
want "$OUT" ARCH_GATE closed "unknown gate value"

OUT="$(gate approved "ARCH_APPROVED='0'" "ARCH_GATE='approved'")"
want "$OUT" ARCH_GATE open "gate approved"

OUT="$(gate carried "ARCH_APPROVED='0'" "ARCH_GATE='carried'")"
want "$OUT" ARCH_GATE open "approval carried from the last review"
want "$OUT" REASON approved_at_last_review "approval carried from the last review"

OUT="$(gate notneeded "ARCH_APPROVED='0'" "ARCH_GATE='not_needed'")"
want "$OUT" ARCH_GATE open "no architecture decisions"

OUT="$(gate failed "ARCH_APPROVED='0'" "ARCH_GATE='failed'")"
want "$OUT" ARCH_GATE open "detector failed"

OUT="$(gate flag "ARCH_APPROVED='1'")"
want "$OUT" ARCH_GATE open "--arch-approved"
want "$OUT" REASON approved_at_invocation "--arch-approved"

OUT="$(gate legacy "RUN_DIR='x'")"
want "$OUT" ARCH_GATE closed "state.env without gate keys"

G() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
packet() {
  local repo="$TMP/repo-$1" dir="$TMP/pk-$1"
  mkdir -p "$repo" "$dir/packet"
  G -C "$repo" init -q -b main
  printf 'a\n' > "$repo/base.txt"; G -C "$repo" add -A; G -C "$repo" commit -q -m base
  printf 'x\n' > "$repo/$2"; G -C "$repo" add -A
  printf '%s\n' "REVIEW_SCOPE='branch'" "CHECKPOINT='skipped'" "CHECKPOINT_SHA='x'" \
    "DIFF_CMD='git diff --cached'" "BASE='main'" "DIFF_BASE='x'" "SOURCE_ROOT='$repo'" \
    "CODEX_REQUESTED='$3'" "CODEX_REASON='$4'" > "$dir/state.env"
  (cd "$repo" && bash "$SCRIPTS/fr-packet.sh" "$dir")
}

OUT="$(packet high auth.py 0 none)"
want "$OUT" RISK high "auth path"
want "$OUT" CODEX_REQUESTED 1 "high risk forces Codex"
want "$OUT" CODEX_REASON risk "high risk forces Codex"

OUT="$(packet normal notes.txt 0 none)"
want "$OUT" RISK normal "plain file"
want "$OUT" CODEX_REQUESTED 0 "normal risk leaves Codex off"

OUT="$(packet asked auth.py 1 asked)"
want "$OUT" CODEX_REASON asked "asked and high risk keeps the user's reason"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
