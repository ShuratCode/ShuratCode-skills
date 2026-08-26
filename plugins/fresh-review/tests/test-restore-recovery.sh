#!/usr/bin/env bash
# test-restore-recovery.sh — the two restore-side fixes shipped in v0.6.1.
#
# Finding 3: a run that dies after `git add -A` but before fr-checkpoint.sh
# records CHECKPOINT leaves state.env without that var. Under `set -u` a bare
# `$CHECKPOINT` in fr-restore.sh aborts the whole restore — and the index the
# user carefully split is left fully staged with nothing to put it back. The fix
# is two-sided: fr-checkpoint.sh writes a pessimistic CHECKPOINT='failed' marker
# BEFORE it stages, and fr-restore.sh treats a missing CHECKPOINT like `failed`,
# restoring the index from the INDEX_TREE preflight recorded.
#
# Finding 4: `git reset --soft` / `git read-tree` failures were ignored, yet the
# script still printed RESET: done / INDEX: restored. A failed undo now reports
# `failed` in its field and exits non-zero.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HERE/../scripts"
for s in fr-preflight.sh fr-checkpoint.sh fr-restore.sh; do
  [ -f "$SCRIPTS/$s" ] || { echo "cannot find $s next to $HERE"; exit 2; }
done

PASS=0; FAIL=0
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

G()   { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
ok()  { printf '  \033[32mok\033[0m    %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s — expected %s, got %s\n' "$1" "$2" "${3:-<empty>}"; FAIL=$((FAIL + 1)); }
key() { grep "^$2:" "$1" | head -1 | sed "s/^$2: *//"; }
want(){ local got; got="$(key "$1" "$2")"
        [ "$got" = "$3" ] && ok "$4 — $2: $got" || bad "$4" "$2=$3" "$2=$got"; }

ORIGIN="$TMP/origin"
G init -q -b main "$ORIGIN"
printf 'a\n' > "$ORIGIN/kept.txt"; printf 'b\n' > "$ORIGIN/other.txt"
G -C "$ORIGIN" add -A && G -C "$ORIGIN" commit -q -m base

# A split index — one staged file, one separately modified unstaged file — is the
# exact shape restore must put back, and the shape `git add -A` flattens.
seed_split() { # worktree
  git clone -q "$ORIGIN" "$1"
  G -C "$1" config user.email t@t; G -C "$1" config user.name t
  G -C "$1" config commit.gpgsign false
  printf 'a\nstaged change\n' > "$1/kept.txt"; G -C "$1" add kept.txt
  printf 'b\nunstaged change\n' > "$1/other.txt"
}

assert_split_restored() { # worktree label
  local staged unstaged
  staged="$(G -C "$1" diff --cached --name-only | sort | tr '\n' ' ')"
  unstaged="$(G -C "$1" diff --name-only | sort | tr '\n' ' ')"
  [ "$staged" = "kept.txt " ]  && ok "$2 — only kept.txt staged again" \
    || bad "$2 staged set" "kept.txt" "$staged"
  [ "$unstaged" = "other.txt " ] && ok "$2 — other.txt still unstaged" \
    || bad "$2 unstaged set" "other.txt" "$unstaged"
}

printf '\n\033[1mfresh-review restore recovery\033[0m\n'

# --- finding 3: interrupted before CHECKPOINT was recorded --------------------
# Preflight records INDEX_TREE; then the run "dies" the moment after `git add -A`
# and before any CHECKPOINT marker — so state.env has no CHECKPOINT at all. This
# is the case that used to abort restore under `set -u`.
WT="$TMP/wt-interrupted"
seed_split "$WT"
(cd "$WT" && bash "$SCRIPTS/fr-preflight.sh" > "$TMP/pf.out" 2>&1)
RUN_DIR="$(key "$TMP/pf.out" RUN_DIR)"
grep -q '^CHECKPOINT=' "$RUN_DIR/state.env" \
  && bad "no CHECKPOINT yet" "state.env without CHECKPOINT" "CHECKPOINT present" \
  || ok "state.env carries no CHECKPOINT before the checkpoint step"
G -C "$WT" add -A   # the mutation that a crash would leave behind

if (cd "$WT" && bash "$SCRIPTS/fr-restore.sh" "$RUN_DIR" > "$TMP/rs.out" 2>&1); then
  ok "restore exits 0 despite the missing CHECKPOINT (no set -u abort)"
else
  bad "restore survives incomplete state" "exit 0" "exit $?"
fi
want "$TMP/rs.out" INDEX restored "incomplete state, index recovered from INDEX_TREE"
want "$TMP/rs.out" RESET skipped_not_committed "incomplete state, no commit to reset"
assert_split_restored "$WT" "incomplete state"

# --- finding 3, writer side: the checkpoint commit fails ----------------------
# With no git identity anywhere, fr-checkpoint.sh stages then fails to commit. The
# pre-stage marker means CHECKPOINT='failed' is persisted, and restore recovers
# the split from INDEX_TREE — the index add already happened.
WT2="$TMP/wt-commitfail"
seed_split "$WT2"
(cd "$WT2" && bash "$SCRIPTS/fr-preflight.sh" > "$TMP/pf2.out" 2>&1)
RUN_DIR2="$(key "$TMP/pf2.out" RUN_DIR)"
# Strip every identity so the WIP commit cannot succeed at any config level.
G -C "$WT2" config --unset user.email; G -C "$WT2" config --unset user.name
(cd "$WT2" && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
   GIT_AUTHOR_NAME= GIT_AUTHOR_EMAIL= GIT_COMMITTER_NAME= GIT_COMMITTER_EMAIL= \
   bash "$SCRIPTS/fr-checkpoint.sh" "$RUN_DIR2" > "$TMP/cp2.out" 2>&1)
want "$TMP/cp2.out" CHECKPOINT failed "a commit with no identity is CHECKPOINT: failed"
(cd "$WT2" && bash "$SCRIPTS/fr-restore.sh" "$RUN_DIR2" > "$TMP/rs2.out" 2>&1)
want "$TMP/rs2.out" INDEX restored "failed checkpoint still restores the index"
assert_split_restored "$WT2" "failed checkpoint"

# --- finding 4: a read-tree failure must be reported, not swallowed -----------
# Point INDEX_TREE at a tree object that does not exist, so `git read-tree` fails.
# The old code printed INDEX: restored and exited 0 regardless.
WT3="$TMP/wt-badtree"
seed_split "$WT3"
(cd "$WT3" && bash "$SCRIPTS/fr-preflight.sh" > "$TMP/pf3.out" 2>&1)
RUN_DIR3="$(key "$TMP/pf3.out" RUN_DIR)"
{ echo "CHECKPOINT='failed'"
  echo "INDEX_TREE='0000000000000000000000000000000000000000'"; } >> "$RUN_DIR3/state.env"
if (cd "$WT3" && bash "$SCRIPTS/fr-restore.sh" "$RUN_DIR3" > "$TMP/rs3.out" 2>&1); then
  bad "read-tree failure exit code" "non-zero" "exit 0"
else
  ok "restore exits non-zero when read-tree fails"
fi
want "$TMP/rs3.out" INDEX failed "a failed read-tree reports INDEX: failed"

# --- finding 3, pr-remote refinement: an interrupted PR run must NOT read-tree --
# A --pr run interrupted before fr-pr-resolve.sh recorded CHECKPOINT leaves PR_REF
# set and CHECKPOINT empty. Nothing of ours ever staged in pr-remote mode, so an
# empty CHECKPOINT there must leave the index alone — restoring the preflight
# snapshot would discard staging the user did during the review.
WT4="$TMP/wt-pr-interrupted"
seed_split "$WT4"
(cd "$WT4" && bash "$SCRIPTS/fr-preflight.sh" --pr 99 > "$TMP/pf4.out" 2>&1)
RUN_DIR4="$(key "$TMP/pf4.out" RUN_DIR)"
grep -q "^PR_REF='99'" "$RUN_DIR4/state.env" \
  && ok "pr-remote preflight records PR_REF without a CHECKPOINT" \
  || bad "pr preflight PR_REF" "PR_REF='99' in state.env" "missing"
printf 'b\nunstaged change\n' > "$WT4/other.txt"; G -C "$WT4" add other.txt  # user stages mid-review
(cd "$WT4" && bash "$SCRIPTS/fr-restore.sh" "$RUN_DIR4" > "$TMP/rs4.out" 2>&1)
want "$TMP/rs4.out" INDEX skipped_nothing_staged "interrupted pr-remote leaves the index untouched"
G -C "$WT4" diff --cached --name-only | grep -qx other.txt \
  && ok "staging done during an interrupted pr-remote review survives restore" \
  || bad "pr-remote index preserved" "other.txt staged" "$(G -C "$WT4" diff --cached --name-only | tr '\n' ' ')"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
