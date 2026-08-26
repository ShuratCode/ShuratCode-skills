#!/usr/bin/env bash
# test-review-mode.sh — the default (findings-only) mode must be unaffected by
# the pr-mode work.
#
# Four of the scripts the default path runs were edited to make room for pr mode:
# preflight gained argument parsing and two new state keys, packet gained
# SOURCE_ROOT, and mutation-check and restore gained a fourth CHECKPOINT value.
# Restore's change in particular rewrote a `!= skipped` test into a named-state
# case, which is only equivalent as long as committed and failed are the exact two
# states where `git add -A` ran. If that equivalence ever breaks, the symptom is
# a staged/unstaged split silently flattened at the end of a review.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HERE/../scripts"
PASS=0; FAIL=0
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

G() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
ok()  { printf '  \033[32mok\033[0m    %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s — expected %s, got %s\n' "$1" "$2" "${3:-<empty>}"; FAIL=$((FAIL + 1)); }
key() { grep "^$2:" "$1" | head -1 | sed "s/^$2: *//"; }
want(){ local got; got="$(key "$1" "$2")"
        [ "$got" = "$3" ] && ok "$4 — $2: $got" || bad "$4" "$2=$3" "$2=$got"; }

ORIGIN="$TMP/origin"; mkdir -p "$ORIGIN"
G -C "$ORIGIN" init -q -b main
printf 'a\n' > "$ORIGIN/kept.txt"; printf 'b\n' > "$ORIGIN/other.txt"
G -C "$ORIGIN" add -A && G -C "$ORIGIN" commit -q -m base

WT="$TMP/wt"
git clone -q "$ORIGIN" "$WT"
# fr-checkpoint.sh runs a plain `git commit`, so the repo under test needs an
# identity of its own. Every real user has one; a CI runner does not, and without
# this the checkpoint fails there and five assertions below read as regressions
# in restore rather than as a missing git config.
git -C "$WT" config user.email fresh-review-test@example.invalid
git -C "$WT" config user.name "fresh-review test"
git -C "$WT" config commit.gpgsign false

# A staged file and a separately modified unstaged file: the split restore has to
# put back exactly as it found it.
printf 'a\nstaged change\n' > "$WT/kept.txt"
G -C "$WT" add kept.txt
printf 'b\nunstaged change\n' > "$WT/other.txt"
printf 'brand new\n' > "$WT/untracked.txt"

printf '\n\033[1mfresh-review default mode\033[0m\n'

(cd "$WT" && bash "$SCRIPTS/fr-preflight.sh" > "$TMP/pf.out" 2>&1)
want "$TMP/pf.out" STATUS ok "preflight with no arguments"
want "$TMP/pf.out" MODE review "preflight with no arguments"
want "$TMP/pf.out" PR_REF none "preflight with no arguments"
want "$TMP/pf.out" REVIEW_SCOPE branch "preflight with no arguments"
want "$TMP/pf.out" SOURCE_ROOT "$WT" "preflight with no arguments"
# Codex is opt-in: the default run must not request it.
want "$TMP/pf.out" CODEX_REQUESTED 0 "preflight with no arguments"
RUN_DIR="$(key "$TMP/pf.out" RUN_DIR)"

# --codex opts the run into Pass C, and it round-trips into state.env.
(cd "$WT" && bash "$SCRIPTS/fr-preflight.sh" --codex > "$TMP/pfcx.out" 2>&1)
want "$TMP/pfcx.out" CODEX_REQUESTED 1 "preflight with --codex"
want "$TMP/pfcx.out" MODE review "preflight with --codex (mode unaffected)"
CXSTATE="$(key "$TMP/pfcx.out" STATE)"
if ( set -eu; . "$CXSTATE"; [ "$CODEX_REQUESTED" = "1" ] ) 2>/dev/null; then
  ok "state.env carries CODEX_REQUESTED=1 under --codex"
else
  bad "state.env CODEX_REQUESTED under --codex" "1" "not re-sourceable or not 1"
fi

# Bad arguments must be rejected loudly, not absorbed into a default mode.
(cd "$WT" && bash "$SCRIPTS/fr-preflight.sh" --mode nonsense > "$TMP/badarg.out" 2>&1)
[ $? -ne 0 ] && ok "an unknown --mode value exits non-zero" \
  || bad "unknown --mode" "non-zero exit" "exit 0"
(cd "$WT" && bash "$SCRIPTS/fr-preflight.sh" --wat > "$TMP/badflag.out" 2>&1)
[ $? -ne 0 ] && ok "an unknown flag exits non-zero" \
  || bad "unknown flag" "non-zero exit" "exit 0"

(cd "$WT" && bash "$SCRIPTS/fr-checkpoint.sh" "$RUN_DIR" > "$TMP/cp.out" 2>&1)
want "$TMP/cp.out" CHECKPOINT committed "checkpoint on a dirty tree"

(cd "$WT" && bash "$SCRIPTS/fr-packet.sh" "$RUN_DIR" > "$TMP/pk.out" 2>&1)
want "$TMP/pk.out" FILES 3 "packet sees the untracked file too"
if grep -qx "SOURCE_ROOT=$WT" "$RUN_DIR/packet/scope.txt"; then
  ok "scope.txt carries SOURCE_ROOT"
else
  bad "scope.txt SOURCE_ROOT" "SOURCE_ROOT=$WT" "$(grep SOURCE_ROOT "$RUN_DIR/packet/scope.txt")"
fi

(cd "$WT" && bash "$SCRIPTS/fr-mutation-check.sh" "$RUN_DIR" > "$TMP/mc.out" 2>&1)
want "$TMP/mc.out" LEAK none "a clean fan-out under CHECKPOINT=committed"
grep -q "^PR_WT_LEAK:" "$TMP/mc.out" \
  && bad "no PR worktree line in review mode" "no PR_WT_LEAK line" "present" \
  || ok "no PR worktree line in review mode"

printf 'a\nstaged change\nreviewer edit\n' > "$WT/kept.txt"
(cd "$WT" && bash "$SCRIPTS/fr-mutation-check.sh" "$RUN_DIR" > "$TMP/mc2.out" 2>&1)
want "$TMP/mc2.out" LEAK detected "a reviewer edit under CHECKPOINT=committed"
(cd "$WT" && bash "$SCRIPTS/fr-mutation-check.sh" "$RUN_DIR" --revert > "$TMP/mc3.out" 2>&1)
want "$TMP/mc3.out" REVERT done "revert is allowed under CHECKPOINT=committed"

(cd "$WT" && bash "$SCRIPTS/fr-restore.sh" "$RUN_DIR" > "$TMP/rs.out" 2>&1)
want "$TMP/rs.out" RESET done "restore after a landed checkpoint"
want "$TMP/rs.out" INDEX restored "restore after a landed checkpoint"
grep -q "^WORKTREE:" "$TMP/rs.out" \
  && bad "no worktree teardown in review mode" "no WORKTREE line" "present" \
  || ok "no worktree teardown in review mode"

STAGED="$(G -C "$WT" diff --cached --name-only | sort | tr '\n' ' ')"
[ "$STAGED" = "kept.txt " ] && ok "only the originally staged file is staged again" \
  || bad "staged set after restore" "kept.txt" "$STAGED"
UNSTAGED="$(G -C "$WT" diff --name-only | sort | tr '\n' ' ')"
[ "$UNSTAGED" = "other.txt " ] && ok "the unstaged modification is still unstaged" \
  || bad "unstaged set after restore" "other.txt" "$UNSTAGED"

# Idempotence: an interrupted run re-runs restore on the next turn.
(cd "$WT" && bash "$SCRIPTS/fr-restore.sh" "$RUN_DIR" > "$TMP/rs2.out" 2>&1)
want "$TMP/rs2.out" RESET skipped_already_reset "restore is idempotent"

# --- preflight writes a re-sourceable state.env even with a quote in a name ----
# Every value goes through kv's single-quote escaping. A branch (or repo path)
# holding a `'` used to unbalance the quoting and break the `.` source in every
# later script; here the whole file must re-source and BRANCH must round-trip.
QWT="$TMP/wt-quote"
git clone -q "$ORIGIN" "$QWT"
G -C "$QWT" checkout -q -b "wip'quote"
printf 'x\n' > "$QWT/f.txt"; G -C "$QWT" add -A
(cd "$QWT" && bash "$SCRIPTS/fr-preflight.sh" > "$TMP/qpf.out" 2>&1)
QSTATE="$(key "$TMP/qpf.out" STATE)"
if ( set -eu; . "$QSTATE"; [ "$BRANCH" = "wip'quote" ] ) 2>/dev/null; then
  ok "state.env re-sources and BRANCH round-trips through a single quote"
else
  bad "state.env quoting" "sources with BRANCH=wip'quote" "source failed or BRANCH wrong"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
