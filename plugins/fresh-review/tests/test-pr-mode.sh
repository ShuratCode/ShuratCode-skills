#!/usr/bin/env bash
# test-pr-mode.sh — fixtures for the pr-review mode scripts.
#
# The traps these exist to catch, in order of how quietly they fail:
#
# 1. Preflight's "nothing_to_review" stop firing on a --pr run. Reviewing someone
#    else's PR from a clean checkout is the *normal* case, and that stop would
#    kill it with a message that reads like a correct answer.
# 2. fr-restore.sh read-tree'ing the pre-review index in pr-remote mode. Nothing
#    was ever staged there, so it would silently discard whatever the user staged
#    while the review ran — a data-losing no-op with no output to notice.
# 3. fr-mutation-check.sh reporting the user's pre-existing uncommitted work as a
#    reviewer leak, which would fire on essentially every pr-remote run.
# 4. SOURCE_ROOT pointing at the user's checkout instead of the PR head, so
#    reviewers open a different commit's file contents than the patch describes.
#
# `gh` is stubbed; the git fetch is real, against a local origin carrying a real
# refs/pull/42/head — the same ref name GitHub serves.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HERE/../scripts"
for s in fr-preflight.sh fr-pr-resolve.sh fr-ddd-vocab.sh fr-restore.sh fr-mutation-check.sh; do
  [ -f "$SCRIPTS/$s" ] || { echo "cannot find $s next to $HERE"; exit 2; }
done

PASS=0; FAIL=0
# Fully resolved: macOS hands out /var/folders/... which git reports back as
# /private/var/folders/..., and several assertions compare paths the scripts
# derived from git against paths the test built itself.
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

G() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }

# --- stub gh ------------------------------------------------------------------
BIN="$TMP/bin"
mkdir -p "$BIN"
cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
# Only `gh pr view` is used. Everything else is a hard error so an accidental
# extra network call shows up as a test failure rather than a silent skip.
[ "$1" = "pr" ] && [ "$2" = "view" ] || { echo "stub gh: unexpected: $*" >&2; exit 9; }
cat "$GH_PR_VIEW_FIXTURE"
EOF
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"

# A PATH holding everything fr-pr-resolve.sh needs except gh, for the
# gh_missing case. Naming the dependency set beats trimming directories out of
# $PATH: on a GitHub runner gh and git share /usr/bin, so dropping the directory
# that carries gh would take git with it and the case would fail for the wrong
# reason — which is exactly how it first failed in CI.
NOGH="$TMP/nogh"
mkdir -p "$NOGH"
for t in bash sh git sed python3 rm mkdir grep cat wc date tr; do
  ln -sf "$(command -v "$t")" "$NOGH/$t"
done

# --- origin, with a PR ref, and a clone ---------------------------------------
ORIGIN="$TMP/origin"
mkdir -p "$ORIGIN"
G -C "$ORIGIN" init -q -b main
echo "one" > "$ORIGIN/app.txt"
G -C "$ORIGIN" add -A && G -C "$ORIGIN" commit -q -m base
BASE_SHA="$(G -C "$ORIGIN" rev-parse HEAD)"

G -C "$ORIGIN" checkout -q -b feature
echo "two" > "$ORIGIN/app.txt"
echo "new file body" > "$ORIGIN/added.txt"
G -C "$ORIGIN" add -A && G -C "$ORIGIN" commit -q -m "pr work"
PR_SHA="$(G -C "$ORIGIN" rev-parse HEAD)"
G -C "$ORIGIN" update-ref refs/pull/42/head "$PR_SHA"
G -C "$ORIGIN" checkout -q main

export GH_PR_VIEW_FIXTURE="$TMP/pr42.json"
python3 -c "
import json
json.dump({'number':42,'title':\"Author's own claim about the change\",
 'url':'https://github.com/acme/widgets/pull/42','state':'OPEN',
 'isCrossRepository':False,'headRefName':'feature',
 'headRefOid':'$PR_SHA','baseRefName':'main'}, open('$TMP/pr42.json','w'))"

fresh_clone() { # dir [gitignore-fresh-review]
  rm -rf "$1"
  git clone -q "$ORIGIN" "$1"
  G -C "$1" remote set-url origin "git@github.com:acme/widgets.git"
  G -C "$1" config --local --add remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  # The clone URL above is what fr-pr-resolve.sh derives the origin slug from;
  # fetches still need to reach the real path, so point them back by insteadOf.
  G -C "$1" config --local "url.$ORIGIN.insteadOf" "git@github.com:acme/widgets.git"
  [ "${2:-}" = "ignore" ] && echo ".fresh-review/" > "$1/.gitignore"
  return 0
}

ok()   { printf '  \033[32mok\033[0m    %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s — expected %s, got %s\n' "$1" "$2" "${3:-<empty>}"; FAIL=$((FAIL + 1)); }
key()  { grep "^$2:" "$1" | head -1 | sed "s/^$2: *//"; }
want() { # outfile field expected label
  local got; got="$(key "$1" "$2")"
  [ "$got" = "$3" ] && ok "$4 — $2: $got" || bad "$4" "$2=$3" "$2=$got"
}

printf '\n\033[1mfresh-review pr mode\033[0m\n'

# --- 1. preflight: --pr must survive a clean checkout -------------------------
# The user's own uncommitted work is created *before* preflight on purpose: it is
# what a real pr-remote run starts from, and the mutation check below has to treat
# it as the baseline rather than as a reviewer's edit.
WT="$TMP/wt1"
fresh_clone "$WT" ignore
echo "user's own work in progress" > "$WT/scratch.txt"
G -C "$WT" add scratch.txt
(cd "$WT" && bash "$SCRIPTS/fr-preflight.sh" --pr 42 > "$TMP/pf.out" 2>"$TMP/pf.err")
want "$TMP/pf.out" STATUS ok "clean checkout + --pr does not stop"
want "$TMP/pf.out" MODE pr "clean checkout + --pr"
want "$TMP/pf.out" PR_REF 42 "clean checkout + --pr"
RUN_DIR="$(key "$TMP/pf.out" RUN_DIR)"
case "$RUN_DIR" in *-pr-42) ok "run dir is named after the PR" ;;
  *) bad "run dir naming" "*-pr-42" "$RUN_DIR" ;; esac

# Without --pr the stop must still fire, or the skip above has been made
# unconditional and every empty run would fan out three reviewers over nothing.
CLEAN_WT="$TMP/wt-clean"
fresh_clone "$CLEAN_WT"
(cd "$CLEAN_WT" && bash "$SCRIPTS/fr-preflight.sh" > "$TMP/pf2.out" 2>&1)
want "$TMP/pf2.out" STATUS stop "clean checkout without --pr still stops"
want "$TMP/pf2.out" STOP_REASON nothing_to_review "clean checkout without --pr"

# --- 2. pr resolve: the happy path -------------------------------------------
(cd "$WT" && bash "$SCRIPTS/fr-pr-resolve.sh" "$RUN_DIR" > "$TMP/pr.out" 2>"$TMP/pr.err")
want "$TMP/pr.out" PR resolved "resolve #42"
want "$TMP/pr.out" PR_NUMBER 42 "resolve #42"
want "$TMP/pr.out" PR_HEAD "$PR_SHA" "resolve #42"
want "$TMP/pr.out" DIFF_BASE "$BASE_SHA" "resolve #42"
want "$TMP/pr.out" HEAD_DRIFT no "resolve #42"
want "$TMP/pr.out" REVIEW_SCOPE pr "resolve #42"

SRC="$(key "$TMP/pr.out" SOURCE_ROOT)"
if [ -f "$SRC/added.txt" ] && [ "$(cat "$SRC/app.txt")" = "two" ]; then
  ok "SOURCE_ROOT holds the PR head's file contents"
else
  bad "SOURCE_ROOT contents" "app.txt=two + added.txt present" "$(ls "$SRC" 2>&1 | tr '\n' ' ')"
fi
if [ "$(cat "$WT/app.txt")" = "one" ]; then
  ok "user's own checkout is left on the base commit"
else
  bad "user checkout untouched" "app.txt=one" "$(cat "$WT/app.txt")"
fi
case "$SRC" in "$WT"/.fresh-review/*) ok "worktree lands in the gitignored in-repo dir" ;;
  *) bad "worktree location" "under $WT/.fresh-review/" "$SRC" ;; esac

# the resolved DIFF_CMD must actually produce the PR's diff
DIFF_CMD="$(key "$TMP/pr.out" DIFF_CMD)"
NAMES="$(cd "$WT" && $DIFF_CMD --name-only | sort | tr '\n' ' ')"
[ "$NAMES" = "added.txt app.txt " ] && ok "DIFF_CMD yields the PR's changed files" \
  || bad "DIFF_CMD file list" "added.txt app.txt" "$NAMES"

# --- 3. mutation check under pr_remote ---------------------------------------
# scratch.txt was staged before preflight ran, so it is in the baseline.
(cd "$WT" && bash "$SCRIPTS/fr-mutation-check.sh" "$RUN_DIR" > "$TMP/mc.out" 2>&1)
want "$TMP/mc.out" LEAK none "pre-existing user dirt is not a reviewer leak"
want "$TMP/mc.out" PR_WT_LEAK none "pre-existing user dirt"

echo "a reviewer 'fixed' something" >> "$SRC/app.txt"
(cd "$WT" && bash "$SCRIPTS/fr-mutation-check.sh" "$RUN_DIR" > "$TMP/mc2.out" 2>&1)
want "$TMP/mc2.out" LEAK detected "a write into the PR worktree is a leak"
want "$TMP/mc2.out" PR_WT_LEAK detected "a write into the PR worktree"
(cd "$WT" && bash "$SCRIPTS/fr-mutation-check.sh" "$RUN_DIR" --revert > "$TMP/mc3.out" 2>&1)
want "$TMP/mc3.out" REVERT refused_pr_remote "revert is refused in pr-remote mode"

# --- 4. restore under pr_remote ----------------------------------------------
echo "staged during the review" > "$WT/late.txt"
G -C "$WT" add late.txt
HEAD_BEFORE="$(G -C "$WT" rev-parse HEAD)"
(cd "$WT" && bash "$SCRIPTS/fr-restore.sh" "$RUN_DIR" > "$TMP/rs.out" 2>&1)
want "$TMP/rs.out" RESET skipped_not_committed "restore does not reset in pr-remote mode"
want "$TMP/rs.out" INDEX skipped_nothing_staged "restore leaves the index alone"
want "$TMP/rs.out" WORKTREE removed "restore tears down the PR worktree"
[ "$(G -C "$WT" rev-parse HEAD)" = "$HEAD_BEFORE" ] && ok "HEAD is unchanged by restore" \
  || bad "HEAD after restore" "$HEAD_BEFORE" "$(G -C "$WT" rev-parse HEAD)"
if G -C "$WT" diff --cached --name-only | grep -qx late.txt; then
  ok "a file staged during the review is still staged afterwards"
else
  bad "index preserved" "late.txt staged" "$(G -C "$WT" diff --cached --name-only | tr '\n' ' ')"
fi
[ -d "$SRC" ] && bad "worktree removed" "gone" "still present" || ok "worktree directory is gone"
if G -C "$WT" rev-parse --verify -q refs/fresh-review/pr-42 >/dev/null; then
  bad "temp ref deleted" "gone" "refs/fresh-review/pr-42 still present"
else
  ok "the temporary PR ref is deleted"
fi
# idempotent: a second restore must not blow up or eat anything
(cd "$WT" && bash "$SCRIPTS/fr-restore.sh" "$RUN_DIR" > "$TMP/rs2.out" 2>&1)
want "$TMP/rs2.out" WORKTREE skipped_none "restore is idempotent"

# --- 5. bad refs, missing tools ----------------------------------------------
resolve_with() { # pr_ref [no-gh]
  local wt="$TMP/wt-neg" out="$TMP/neg.out"
  fresh_clone "$wt"
  (cd "$wt" && bash "$SCRIPTS/fr-preflight.sh" --pr "$1" > "$TMP/neg-pf.out" 2>&1)
  local rd; rd="$(key "$TMP/neg-pf.out" RUN_DIR)"
  if [ "${2:-}" = "no-gh" ]; then
    (cd "$wt" && PATH="$NOGH" bash "$SCRIPTS/fr-pr-resolve.sh" "$rd" > "$out" 2>&1)
  else
    (cd "$wt" && bash "$SCRIPTS/fr-pr-resolve.sh" "$rd" > "$out" 2>&1)
  fi
  printf '%s' "$out"
}
want "$(resolve_with 'not-a-pr')" REASON bad_pr_ref "a ref that is neither a number nor a pull URL"
want "$(resolve_with 'https://github.com/other/repo/pull/7')" REASON foreign_repo "a pull URL for another repo"
want "$(resolve_with 42 no-gh)" REASON gh_missing "gh not installed"
want "$(resolve_with 'not-a-pr')" PR unresolved "an unresolved ref reports unresolved"

# --- 6. ddd vocabulary resolution -------------------------------------------
vocab_in() { # setup-fn
  local wt="$TMP/wt-ddd"
  fresh_clone "$wt" ignore
  "$1" "$wt"
  (cd "$wt" && bash "$SCRIPTS/fr-preflight.sh" --mode pr > "$TMP/v-pf.out" 2>&1)
  local rd; rd="$(key "$TMP/v-pf.out" RUN_DIR)"
  echo "$rd" > "$TMP/v-rd"
  (cd "$wt" && bash "$SCRIPTS/fr-ddd-vocab.sh" "$rd" > "$TMP/v.out" 2>&1)
  printf '%s' "$TMP/v.out"
}

with_glossary() {
  mkdir -p "$1/.lattice/standards"
  cat > "$1/.lattice/standards/ddd-principles.md" <<'EOF'
---
mode: overlay
---
## 1. Aggregate Design Rules
Consistency boundaries only.
## 10. Ubiquitous Language
- **Widget** — the thing a customer configures and orders.
- **Widget Run** — one attempt to build a Widget.
## 11. Validation Checklist
- [ ] something
EOF
  echo dirt > "$1/dirt.txt"
}
with_doc_no_glossary() {
  mkdir -p "$1/.lattice/standards"
  printf -- '---\nmode: override\n---\n## 1. Aggregate Design Rules\ntext\n' \
    > "$1/.lattice/standards/ddd-principles.md"
  echo dirt > "$1/dirt.txt"
}
with_nothing() { echo dirt > "$1/dirt.txt"; }

OUT="$(vocab_in with_glossary)"
want "$OUT" VOCAB ddd-principles "a repo with a ddd-principles glossary"
want "$OUT" DDD_MODE overlay "a repo with a ddd-principles glossary"
want "$OUT" GLOSSARY extracted "a repo with a ddd-principles glossary"
BRIEF="$(key "$OUT" BRIEF)"
if grep -q "Widget Run" "$BRIEF" && ! grep -q "Consistency boundaries only" "$BRIEF"; then
  ok "the brief carries the glossary and not the unrelated sections"
else
  bad "brief contents" "Ubiquitous Language section only" "$(head -c 200 "$BRIEF" | tr '\n' ' ')"
fi

OUT="$(vocab_in with_doc_no_glossary)"
want "$OUT" VOCAB ddd-principles "a ddd-principles doc with no glossary section"
want "$OUT" DDD_MODE override "a ddd-principles doc with no glossary section"
want "$OUT" GLOSSARY headings_only "a ddd-principles doc with no glossary section"

OUT="$(vocab_in with_nothing)"
want "$OUT" VOCAB atom-defaults "a repo with no ddd-principles doc"
want "$OUT" DDD_DOC none "a repo with no ddd-principles doc"
want "$OUT" GLOSSARY defaults "a repo with no ddd-principles doc"
BRIEF="$(key "$OUT" BRIEF)"
grep -q "no domain meaning" "$BRIEF" \
  && ok "the fallback brief warns against inventing domain meaning" \
  || bad "fallback brief" "an infrastructural-change warning" "missing"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
