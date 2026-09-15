#!/usr/bin/env bash
# test-hook-isolation.sh — fresh-review's own git operations must never run a
# hook from the tree under review. Two commands touch untrusted content and both
# would otherwise fire a hook on the reviewer's host, before any review happens:
#
#   fr-checkpoint.sh  `git commit --no-verify` — --no-verify skips pre-commit and
#     commit-msg but NOT prepare-commit-msg. Reviewing a locally checked-out
#     untrusted branch whose tree sets core.hooksPath at a tracked dir runs that
#     hook during the WIP checkpoint. This is the reproducing RCE.
#   fr-pr-resolve.sh  `git worktree add`       — runs post-checkout. A reviewer
#     whose checkout has core.hooksPath pointing at an in-repo dir has that hook
#     fired as a side effect of materializing the PR head (relative hooksPath
#     resolves against the invoking worktree, so its own dir is what git reads).
#
# Both are neutralized with `-c core.hooksPath=/dev/null`. Each case first proves
# the hook is live under the plain git command — the positive control, so the
# assertion cannot pass merely because the fixture stopped triggering the hook —
# then asserts the fresh-review script leaves it unfired while still doing its job.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HERE/../scripts"
for s in fr-preflight.sh fr-checkpoint.sh fr-pr-resolve.sh; do
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

printf '\n\033[1mfresh-review hook isolation\033[0m\n'

# --- fr-checkpoint: prepare-commit-msg must not run ---------------------------
# The origin ships a tracked prepare-commit-msg; each clone points core.hooksPath
# at it, modelling a reviewer whose repo uses in-repo git hooks.
CP_ORIGIN="$TMP/cp-origin"
G init -q -b main "$CP_ORIGIN"
mkdir "$CP_ORIGIN/.githooks"
cat > "$CP_ORIGIN/.githooks/prepare-commit-msg" <<EOF
#!/usr/bin/env bash
: > "$TMP/FIRED_prepare_commit_msg"
EOF
chmod +x "$CP_ORIGIN/.githooks/prepare-commit-msg"
echo base > "$CP_ORIGIN/app.txt"
G -C "$CP_ORIGIN" add -A && G -C "$CP_ORIGIN" commit -q -m base

clone_hooked() { # dir
  git clone -q "$CP_ORIGIN" "$1"
  G -C "$1" config user.email t@t; G -C "$1" config user.name t
  G -C "$1" config commit.gpgsign false
  G -C "$1" config core.hooksPath .githooks
}

# positive control: a plain `git commit --no-verify` fires the hook.
CP_CTRL="$TMP/cp-control"
clone_hooked "$CP_CTRL"
echo dirt > "$CP_CTRL/dirt.txt"; G -C "$CP_CTRL" add -A
rm -f "$TMP/FIRED_prepare_commit_msg"
G -C "$CP_CTRL" commit --no-verify -q -m control >/dev/null 2>&1 || true
[ -f "$TMP/FIRED_prepare_commit_msg" ] \
  && ok "control: prepare-commit-msg fires under a plain --no-verify commit" \
  || bad "checkpoint control fixture" "hook fires without the guard" "did not fire"

# subject: fr-checkpoint.sh commits the WIP checkpoint without firing it.
CP_SUBJ="$TMP/cp-subject"
clone_hooked "$CP_SUBJ"
echo dirt > "$CP_SUBJ/dirt.txt"; G -C "$CP_SUBJ" add dirt.txt
(cd "$CP_SUBJ" && bash "$SCRIPTS/fr-preflight.sh" > "$TMP/cp-pf.out" 2>&1)
CP_RUN_DIR="$(key "$TMP/cp-pf.out" RUN_DIR)"
rm -f "$TMP/FIRED_prepare_commit_msg"
(cd "$CP_SUBJ" && bash "$SCRIPTS/fr-checkpoint.sh" "$CP_RUN_DIR" > "$TMP/cp.out" 2>&1)
want "$TMP/cp.out" CHECKPOINT committed "checkpoint still commits with hooks disabled"
[ -f "$TMP/FIRED_prepare_commit_msg" ] \
  && bad "checkpoint hook isolation" "no marker" "prepare-commit-msg FIRED" \
  || ok "checkpoint does not run the untrusted prepare-commit-msg hook"

# --- fr-pr-resolve: post-checkout must not run -------------------------------
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "pr" ] && [ "$2" = "view" ] || { echo "stub gh: unexpected: $*" >&2; exit 9; }
cat "$GH_PR_VIEW_FIXTURE"
EOF
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"

PR_ORIGIN="$TMP/pr-origin"
G init -q -b main "$PR_ORIGIN"
echo one > "$PR_ORIGIN/app.txt"
G -C "$PR_ORIGIN" add -A && G -C "$PR_ORIGIN" commit -q -m base
G -C "$PR_ORIGIN" checkout -q -b feature
echo two > "$PR_ORIGIN/app.txt"
G -C "$PR_ORIGIN" add -A && G -C "$PR_ORIGIN" commit -q -m "pr work"
PR_SHA="$(G -C "$PR_ORIGIN" rev-parse HEAD)"
G -C "$PR_ORIGIN" update-ref refs/pull/7/head "$PR_SHA"
G -C "$PR_ORIGIN" checkout -q main

export GH_PR_VIEW_FIXTURE="$TMP/pr7.json"
python3 -c "
import json
json.dump({'number':7,'title':'x','url':'https://github.com/acme/widgets/pull/7',
 'state':'OPEN','isCrossRepository':False,'headRefName':'feature',
 'headRefOid':'$PR_SHA','baseRefName':'main'}, open('$TMP/pr7.json','w'))"

clone_pr() { # dir
  git clone -q "$PR_ORIGIN" "$1"
  G -C "$1" config user.email t@t; G -C "$1" config user.name t
  G -C "$1" config commit.gpgsign false
  G -C "$1" remote set-url origin "git@github.com:acme/widgets.git"
  G -C "$1" config --local --add remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  G -C "$1" config --local "url.$PR_ORIGIN.insteadOf" "git@github.com:acme/widgets.git"
  echo ".fresh-review/" > "$1/.gitignore"
  # The reviewer's checkout carries an in-repo hooks dir wired via core.hooksPath;
  # a relative hooksPath resolves against this worktree, so this is where the
  # post-checkout on `git worktree add` is read from.
  mkdir "$1/.githooks"
  cat > "$1/.githooks/post-checkout" <<EOF2
#!/usr/bin/env bash
: > "$TMP/FIRED_post_checkout"
EOF2
  chmod +x "$1/.githooks/post-checkout"
  G -C "$1" config core.hooksPath .githooks
}

# positive control: a plain `git worktree add` fires post-checkout.
PR_CTRL="$TMP/pr-control"
clone_pr "$PR_CTRL"
rm -f "$TMP/FIRED_post_checkout"
G -C "$PR_CTRL" worktree add --quiet --detach "$PR_CTRL/.fresh-review/ctrl-wt" "$PR_SHA" >/dev/null 2>&1 || true
[ -f "$TMP/FIRED_post_checkout" ] \
  && ok "control: post-checkout fires under a plain worktree add" \
  || bad "pr control fixture" "post-checkout fires without the guard" "did not fire"
G -C "$PR_CTRL" worktree remove --force "$PR_CTRL/.fresh-review/ctrl-wt" >/dev/null 2>&1 || true

# subject: fr-pr-resolve.sh materializes the PR head without firing it.
PR_SUBJ="$TMP/pr-subject"
clone_pr "$PR_SUBJ"
(cd "$PR_SUBJ" && bash "$SCRIPTS/fr-preflight.sh" --pr 7 > "$TMP/pr-pf.out" 2>&1)
PR_RUN_DIR="$(key "$TMP/pr-pf.out" RUN_DIR)"
rm -f "$TMP/FIRED_post_checkout"
(cd "$PR_SUBJ" && bash "$SCRIPTS/fr-pr-resolve.sh" "$PR_RUN_DIR" > "$TMP/pr.out" 2>&1)
want "$TMP/pr.out" PR resolved "pr resolve still materializes the worktree with hooks disabled"
[ -f "$TMP/FIRED_post_checkout" ] \
  && bad "pr worktree hook isolation" "no marker" "post-checkout FIRED" \
  || ok "pr resolve does not run the reviewer's post-checkout hook"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
