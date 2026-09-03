#!/usr/bin/env bash
# test-worktree-cleanup.sh — fixtures for worktree-cleanup.sh.
#
# This tool DELETES git worktrees, so every test pins a safety property, not
# just "the script ran". The classifier must keep any worktree that holds
# uncommitted changes (tracked or untracked), unpublished commits, or a lock,
# and the remover must refuse those same worktrees unless --force. A test that
# only checked exit codes would pass a script that deleted everything.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/../scripts/worktree-cleanup.sh"
[ -f "$S" ] || { echo "cannot find worktree-cleanup.sh next to $HERE"; exit 2; }

PASS=0; FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

GA=(-c user.email=t@t -c user.name=t -c commit.gpgsign=false)

ok()   { PASS=$((PASS+1)); printf '  \033[32mok\033[0m    %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; }
# assert that running the tool with the given args produces stdout containing PATTERN
grep_ok() { # desc pattern -- args...
  local desc="$1" pat="$2"; shift 2
  local out; out="$(bash "$S" "$@" 2>&1)"
  if printf '%s\n' "$out" | grep -qE "$pat"; then ok "$desc"; else
    bad "$desc — expected /$pat/, got:"; printf '%s\n' "$out" | sed 's/^/      /'; fi
}
grep_absent() { # desc pattern -- args...
  local desc="$1" pat="$2"; shift 2
  local out; out="$(bash "$S" "$@" 2>&1)"
  if printf '%s\n' "$out" | grep -qE "$pat"; then
    bad "$desc — did not expect /$pat/, got:"; printf '%s\n' "$out" | sed 's/^/      /'
  else ok "$desc"; fi
}

# --- build a fixture repo with a bare remote and worktrees in every state ----
mkfixture() { # repo-dir
  local R="$1" RM="$1-remote.git"
  rm -rf "$R" "$RM"
  git init -q --bare "$RM"
  git init -q "$R"
  ( cd "$R"
    git "${GA[@]}" commit -q --allow-empty -m init
    git branch -M main
    git remote add origin "$RM"
    git push -q -u origin main
    git worktree add -q wts/clean HEAD                       # clean + published
    git worktree add -q wts/dirty HEAD                        # modified tracked file
    echo edit >> wts/dirty/anything.txt; git -C wts/dirty add -A
    git worktree add -q wts/untracked HEAD                    # untracked file only
    echo new > wts/untracked/scratch.txt
    git worktree add -q -b feature wts/unpub HEAD             # committed but unpushed
    cd wts/unpub; echo x > work.txt; git add work.txt
    git "${GA[@]}" commit -q -m "unpublished work" )
}

echo "worktree-cleanup: safety classification + removal"

R="$TMP/repo"
mkfixture "$R"

# 1. dry run classifies each state correctly
grep_ok  "clean+published -> REMOVE"        'REMOVE +wts/clean'          --repo "$R"
grep_ok  "modified tracked -> KEEP dirty"   'KEEP +wts/dirty +dirty'     --repo "$R"
grep_ok  "untracked file -> KEEP dirty"     'KEEP +wts/untracked +dirty' --repo "$R"
grep_ok  "unpushed commit -> KEEP unpub"    'KEEP +wts/unpub +1 unpublished' --repo "$R"
grep_ok  "dry run deletes nothing (banner)" 'nothing deleted'           --repo "$R"
grep_ok  "dry run prints local-ref caveat"  'local remote-tracking refs' --repo "$R"

# 2. dry run must not have removed anything
if git -C "$R" worktree list | grep -q 'wts/clean'; then ok "dry run left worktrees intact"; else bad "dry run deleted a worktree"; fi

# 3. remove mode refuses unsafe, removes approved
grep_ok  "refuses dirty without --force"    'REFUSED.*wts/dirty'   --repo "$R" --remove "$R/wts/dirty"
grep_ok  "refuses unpublished w/o --force"  'REFUSED.*wts/unpub'   --repo "$R" --remove "$R/wts/unpub"
grep_ok  "removes an approved clean one"    'REMOVED.*wts/clean'   --repo "$R" --remove "$R/wts/clean"
if git -C "$R" worktree list | grep -q 'wts/clean'; then bad "approved clean worktree not removed"; else ok "approved clean worktree gone"; fi
if git -C "$R" worktree list | grep -q 'wts/dirty'; then ok "refused dirty worktree still present"; else bad "dirty worktree was deleted"; fi

# 4. unknown path is skipped, not removed
grep_ok  "unknown path -> SKIPPED"          'SKIPPED.*not a worktree' --repo "$R" --remove "$R/wts/ghost"

# 5. primary worktree is never removable, even with --force
grep_ok  "primary refused even with --force" 'REFUSED.*primary'    --repo "$R" --remove "$R" --force

# 6. --force removes a dirty worktree and says what it discarded
grep_ok  "--force removes dirty"            'FORCED.*wts/dirty'    --repo "$R" --remove "$R/wts/dirty" --force
if git -C "$R" worktree list | grep -q 'wts/dirty'; then bad "--force did not remove dirty"; else ok "--force removed dirty worktree"; fi

# 7. trailing valueless flags exit 2 instead of hanging
if ( bash "$S" --repo "$R" --remove </dev/null >/dev/null 2>&1 ); then
  bad "trailing --remove should exit non-zero"
else
  rc=$?; [ "$rc" -eq 2 ] && ok "trailing --remove exits 2 (no hang)" || bad "trailing --remove exit was $rc, want 2"
fi

# 8. relative --remove path resolves against --repo, not the cwd
mkfixture "$TMP/repo2"
( cd "$TMP"   # cwd is NOT the repo
  out="$(bash "$S" --repo "$TMP/repo2" --remove "wts/clean" 2>&1)"
  if printf '%s\n' "$out" | grep -q 'REMOVED'; then ok "relative path resolves against --repo from another cwd"; else
    bad "relative path did not resolve against --repo:"; printf '%s\n' "$out" | sed 's/^/      /'; fi )

# 9. prunable: a worktree whose directory is gone
rm -rf "$TMP/repo2/wts/dirty"
grep_ok  "missing dir -> PRUNABLE"          'PRUNABLE.*wts/dirty'  --repo "$TMP/repo2"
grep_ok  "--prune clears the stale entry"   'wts/dirty'            --repo "$TMP/repo2" --prune
if git -C "$TMP/repo2" worktree list --porcelain | grep -q 'wts/dirty'; then bad "--prune left a stale entry"; else ok "--prune removed the stale entry"; fi

# 10. no remote at all -> everything kept
NR="$TMP/noremote"; rm -rf "$NR"; git init -q "$NR"
( cd "$NR"; git "${GA[@]}" commit -q --allow-empty -m init; git branch -M main
  git worktree add -q wts/x HEAD )
grep_ok  "no remote -> KEEP everything"     'KEEP +wts/x +no remote' --repo "$NR"

# 11. bad usage exits 2
if ( bash "$S" --bogus >/dev/null 2>&1 ); then bad "unknown flag should exit 2"; else
  rc=$?; [ "$rc" -eq 2 ] && ok "unknown flag exits 2" || bad "unknown flag exit was $rc"; fi

# 12. not a git repo exits 2
if ( bash "$S" --repo "$TMP" >/dev/null 2>&1 ); then bad "non-repo should exit 2"; else
  rc=$?; [ "$rc" -eq 2 ] && ok "non-repo dir exits 2" || bad "non-repo exit was $rc"; fi

echo
if [ "$FAIL" -gt 0 ]; then
  printf '\033[31m%d passed, %d failed.\033[0m\n' "$PASS" "$FAIL"
  exit 1
fi
printf '\033[32m%d passed, 0 failed.\033[0m\n' "$PASS"
