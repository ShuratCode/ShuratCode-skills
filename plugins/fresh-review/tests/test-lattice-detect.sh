#!/usr/bin/env bash
# test-lattice-detect.sh — fixtures for fr-lattice-detect.sh, the gate on Pass A.
#
# Lattice review runs only when this change has a lattice design or context doc.
# Traps:
# 1. Running lattice for any repo that has a .lattice dir. A doc must match this
#    change: by branch, by the files it names, or by being in the diff.
# 2. Missing a doc in a sub-project (.lattice under activate/, not the repo root)
#    whose paths are relative to that sub-project.
# 3. Matching on one shared file when the change touches many.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HERE/../scripts"

PASS=0; FAIL=0
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

ok()  { printf '  ok   %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL %s\n       want %s / got %s\n' "$1" "$2" "$3"; FAIL=$((FAIL + 1)); }
key() { printf '%s\n' "$1" | grep "^$2:" | head -1 | sed "s/^$2: //"; }
want() { local got; got="$(key "$1" "$2")"; [ "$got" = "$3" ] && ok "$4 — $2=$3" || bad "$4" "$2=$3" "$2=$got"; }

SRC="$TMP/src"
mkdir -p "$SRC/activate/.lattice/contexts" "$SRC/activate/.lattice/standards"
printf -- '---\nfeature: x\nbranch: feat/x\n---\nTouches `backoffice/a.py` and `backoffice/b.py`.\n' \
  > "$SRC/activate/.lattice/contexts/x.md"
printf 'standards, not a context\n' > "$SRC/activate/.lattice/standards/clean-code.md"

detect() { # branch name-status-lines
  rm -rf "$TMP/run"; mkdir -p "$TMP/run/packet"
  printf "SOURCE_ROOT='%s'\nREPO_ROOT='%s'\nBRANCH='%s'\n" "$SRC" "$SRC" "$1" > "$TMP/run/state.env"
  printf '%b' "$2" > "$TMP/run/packet/files.txt"
  bash "$SCRIPTS/fr-lattice-detect.sh" "$TMP/run"
}

OUT="$(detect feat/x 'M\tother.py\n')"
want "$OUT" LATTICE_CONTEXT yes "frontmatter branch matches"
want "$OUT" LATTICE_REASON branch_match "reason"

OUT="$(detect main 'M\tactivate/backoffice/a.py\nM\tactivate/backoffice/b.py\nM\tz.py\n')"
want "$OUT" LATTICE_CONTEXT yes "a sub-project doc names two changed files"
want "$OUT" LATTICE_DOC activate/.lattice/contexts/x.md "the doc path"

OUT="$(detect main 'M\tactivate/backoffice/a.py\nM\tz.py\n')"
want "$OUT" LATTICE_CONTEXT no "one shared file is not enough"

OUT="$(detect main 'A\tactivate/.lattice/contexts/new.md\nM\tz.py\n')"
want "$OUT" LATTICE_REASON diff_touches_context "the diff adds a context doc"

OUT="$(detect main 'M\tactivate/.lattice/standards/clean-code.md\n')"
want "$OUT" LATTICE_CONTEXT no "a standards edit is not a feature context"

grep -q "^LATTICE_CONTEXT='no'" "$TMP/run/state.env" && ok "the answer lands in state.env" \
  || bad "state.env" "LATTICE_CONTEXT='no'" "$(cat "$TMP/run/state.env")"

rm -rf "$SRC/activate/.lattice"
OUT="$(detect feat/x 'M\tz.py\n')"
want "$OUT" LATTICE_REASON no_lattice_dir "no .lattice dir at all"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
