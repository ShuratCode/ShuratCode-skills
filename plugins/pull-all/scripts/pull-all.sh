#!/usr/bin/env bash
# pull-all.sh — recursively find git repos under a path and fast-forward their
# main branch. Written for bash 3.2 (macOS /bin/bash): no associative arrays,
# no `wait -n`, no mapfile.

set -uo pipefail

ROOT=""
BRANCH=""
DEPTH=4
JOBS=8
DRY=0
TIMEOUT=120
LOG=""
HIDDEN=0
CREATE=0

usage() {
  cat <<'EOF'
usage: pull-all.sh [options] [PATH]

Finds every git repo under PATH (default: cwd) and brings its main branch up to
date with origin. Never switches branches, never merges non-fast-forward,
never touches a dirty working tree.

options:
  -b, --branch NAME   target branch for every repo (default: per-repo detection
                      via origin/HEAD, then main, then master, then trunk)
  -d, --depth N       how deep to search for .git (default 4)
  -j, --jobs N        repos to process in parallel (default 8)
  -t, --timeout SECS  per-repo network timeout (default 120)
  -n, --dry-run       fetch and report, but move no local ref
      --hidden        also descend into dot-directories (~/.nvm, ~/.oh-my-zsh …),
                      which are skipped by default
      --create        create the target branch locally when it is missing
                      (default: report SKIPPED and leave the repo alone)
  -l, --log FILE      verbose log path (default: mktemp)
  -h, --help          this

exit: 0 all good; 1 at least one repo DIVERGED or FAILED; 2 bad usage.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -b|--branch)  BRANCH="${2:-}"; shift 2 ;;
    -d|--depth)   DEPTH="${2:-}"; shift 2 ;;
    -j|--jobs)    JOBS="${2:-}"; shift 2 ;;
    -t|--timeout) TIMEOUT="${2:-}"; shift 2 ;;
    -l|--log)     LOG="${2:-}"; shift 2 ;;
    -n|--dry-run) DRY=1; shift ;;
    --hidden)     HIDDEN=1; shift ;;
    --create)     CREATE=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    -*)           echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)            [ -n "$ROOT" ] && { echo "only one PATH allowed" >&2; exit 2; }
                  ROOT="$1"; shift ;;
  esac
done

[ -n "$ROOT" ] || ROOT="$PWD"
ROOT="${ROOT/#\~/$HOME}"
[ -d "$ROOT" ] || { echo "not a directory: $ROOT" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd -P)"

case "$DEPTH$JOBS$TIMEOUT" in *[!0-9]*) echo "depth/jobs/timeout must be integers" >&2; exit 2 ;; esac
[ "$JOBS" -ge 1 ] || JOBS=1

[ -n "$LOG" ] || LOG="$(mktemp -t pull-all)"
: >"$LOG"
RESULTS="$(mktemp -d -t pull-all-results)"
trap 'rm -rf "$RESULTS"' EXIT

export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/usr/bin/true
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=10}"

run_timeout() {
  local secs="$1"; shift
  "$@" & local pid=$!
  local n=0 max=$((secs * 10))
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$n" -ge "$max" ]; then
      kill -9 "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      return 124
    fi
    sleep 0.1; n=$((n + 1))
  done
  wait "$pid"
}

detect_branch() {
  local r="$1" b c
  b="$(git -C "$r" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
  b="${b#origin/}"
  if [ -z "$b" ]; then
    for c in main master trunk; do
      if git -C "$r" show-ref --verify --quiet "refs/remotes/origin/$c"; then b="$c"; break; fi
    done
  fi
  printf '%s' "$b"
}

relpath() {
  local p="${1#$ROOT}"; p="${p#/}"
  [ -n "$p" ] || p="$(basename "$1")"
  printf '%s' "$p"
}

emit() { printf '%s\t%s\t%s\n' "$1" "$(relpath "$2")" "$3" >"$RESULTS/$4"; }

process_repo() {
  local repo="$1" slot="$2"

  { echo; echo "### $(relpath "$repo")"; } >>"$LOG"

  if ! git -C "$repo" remote get-url origin >/dev/null 2>&1; then
    emit SKIPPED "$repo" "no origin remote" "$slot"; return
  fi

  local out rc
  out="$(run_timeout "$TIMEOUT" git -C "$repo" fetch --prune --no-tags origin 2>&1)"; rc=$?
  printf '%s\n' "$out" >>"$LOG"
  if [ "$rc" -eq 124 ]; then
    emit FAILED "$repo" "fetch timed out after ${TIMEOUT}s" "$slot"; return
  elif [ "$rc" -ne 0 ]; then
    emit FAILED "$repo" "fetch failed: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-120)" "$slot"; return
  fi

  local target="$BRANCH"
  [ -n "$target" ] || target="$(detect_branch "$repo")"
  if [ -z "$target" ]; then
    emit SKIPPED "$repo" "cannot determine default branch" "$slot"; return
  fi
  if ! git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$target"; then
    emit SKIPPED "$repo" "origin/$target does not exist" "$slot"; return
  fi

  # A bare repo still reports a symbolic HEAD, so asking for the branch name is not
  # enough to know whether anything is checked out here. Treating it as checked out
  # sends us into `merge --ff-only`, which dies with "must be run in a work tree".
  local cur
  if [ "$(git -C "$repo" rev-parse --is-bare-repository 2>/dev/null)" = "true" ]; then
    cur="(bare)"
  else
    cur="$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null)"
    [ -n "$cur" ] || cur="(detached)"
  fi

  if ! git -C "$repo" show-ref --verify --quiet "refs/heads/$target"; then
    if [ "$CREATE" -eq 0 ]; then
      emit SKIPPED "$repo" "no local $target (on $cur); origin/$target fetched — pass --create to make it" "$slot"; return
    fi
    if [ "$DRY" -eq 1 ]; then
      emit CREATED "$repo" "would create $target from origin/$target (on $cur)" "$slot"; return
    fi
    if out="$(git -C "$repo" fetch origin "$target:$target" 2>&1)"; then
      emit CREATED "$repo" "created $target from origin/$target (on $cur)" "$slot"
    else
      printf '%s\n' "$out" >>"$LOG"
      emit FAILED "$repo" "could not create $target" "$slot"
    fi
    return
  fi

  local counts ahead behind
  counts="$(git -C "$repo" rev-list --left-right --count "refs/heads/$target...refs/remotes/origin/$target" 2>/dev/null)"
  ahead="$(printf '%s' "$counts" | awk '{print $1+0}')"
  behind="$(printf '%s' "$counts" | awk '{print $2+0}')"

  if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
    emit DIVERGED "$repo" "$target is $ahead ahead / $behind behind origin — resolve by hand" "$slot"; return
  fi
  if [ "$behind" -eq 0 ]; then
    if [ "$ahead" -gt 0 ]; then
      emit CURRENT "$repo" "$target up to date ($ahead unpushed)" "$slot"
    else
      emit CURRENT "$repo" "$target up to date" "$slot"
    fi
    return
  fi

  if [ "$cur" = "$target" ]; then
    # Fail closed: a status read that *errors* must not be mistaken for a clean tree.
    local st
    if ! st="$(git -C "$repo" status --porcelain --untracked-files=no 2>>"$LOG")"; then
      emit SKIPPED "$repo" "cannot read status on $target ($behind behind)" "$slot"; return
    fi
    if [ -n "$st" ]; then
      emit SKIPPED "$repo" "dirty working tree on $target ($behind behind)" "$slot"; return
    fi
    if [ "$DRY" -eq 1 ]; then
      emit UPDATED "$repo" "would fast-forward $target +$behind" "$slot"; return
    fi
    if out="$(git -C "$repo" merge --ff-only "origin/$target" 2>&1)"; then
      printf '%s\n' "$out" >>"$LOG"
      emit UPDATED "$repo" "$target +$behind" "$slot"
    else
      printf '%s\n' "$out" >>"$LOG"
      emit FAILED "$repo" "ff-only merge failed: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-120)" "$slot"
    fi
    return
  fi

  # target is not checked out here, but a linked worktree may hold it — git refuses to
  # fetch into a branch checked out anywhere, so say so instead of reporting FAILED.
  local wt
  wt="$(git -C "$repo" worktree list --porcelain 2>/dev/null \
        | awk -v b="branch refs/heads/$target" '$0=="worktree"{w=""} /^worktree /{w=substr($0,10)} $0==b{print w; exit}')"
  if [ -n "$wt" ]; then
    emit SKIPPED "$repo" "$target is checked out in linked worktree $wt ($behind behind)" "$slot"; return
  fi

  # target is not checked out: move the local ref without touching the worktree
  if [ "$DRY" -eq 1 ]; then
    emit UPDATED "$repo" "would fast-forward $target +$behind in place (on $cur)" "$slot"; return
  fi
  if out="$(git -C "$repo" fetch origin "$target:$target" 2>&1)"; then
    printf '%s\n' "$out" >>"$LOG"
    emit UPDATED "$repo" "$target +$behind in place (on $cur)" "$slot"
  else
    printf '%s\n' "$out" >>"$LOG"
    emit FAILED "$repo" "in-place update of $target failed" "$slot"
  fi
}

PRUNE='-name node_modules -o -name venv -o -name vendor -o -name Library -o -name Pods'
# Dot-directories are tool checkouts (~/.nvm, ~/.oh-my-zsh, ~/.terraform), not
# work repos. `! -name .git` is load-bearing: .git is itself a dot-name, so
# pruning dot-dirs without the exclusion prunes every repo before -print sees it.
[ "$HIDDEN" -eq 1 ] || PRUNE="$PRUNE -o \( -name '.[^.]*' ! -name .git \)"

# shellcheck disable=SC2086
REPO_HITS="$(eval find "$(printf '%q' "$ROOT")" -maxdepth "$DEPTH" \
  -type d \\\( $PRUNE \\\) -prune -o -name .git -print 2>/dev/null | sort)"

started=0 skipped_nested=0 slot=0
SECONDS=0
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  repo="$(dirname "$hit")"
  if [ -f "$hit" ]; then
    slot=$((slot + 1))
    emit SKIPPED "$repo" "submodule or linked worktree" "$(printf '%04d' "$slot")"
    skipped_nested=$((skipped_nested + 1))
    continue
  fi
  slot=$((slot + 1))
  while [ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$JOBS" ]; do sleep 0.1; done
  process_repo "$repo" "$(printf '%04d' "$slot")" &
  started=$((started + 1))
done <<EOF
$REPO_HITS
EOF
wait

echo "=== PULL-ALL SUMMARY ==="
printf 'root: %s   branch: %s   jobs: %s   dry-run: %s\n' \
  "$ROOT" "${BRANCH:-auto}" "$JOBS" "$([ "$DRY" -eq 1 ] && echo yes || echo no)"

ALL="$(cat "$RESULTS"/* 2>/dev/null)"
if [ -z "$ALL" ]; then
  echo "no git repos found under $ROOT (searched to depth $DEPTH)"
  echo "LOG: $LOG"
  exit 0
fi

rank() { case "$1" in FAILED) echo 1;; DIVERGED) echo 2;; SKIPPED) echo 3;; UPDATED) echo 4;; CREATED) echo 5;; *) echo 6;; esac; }
printf '%s\n' "$ALL" | while IFS="$(printf '\t')" read -r st path detail; do
  [ -n "$st" ] || continue
  printf '%s\t%s\t%s\t%s\n' "$(rank "$st")" "$st" "$path" "$detail"
done | sort -t"$(printf '\t')" -k1,1n -k3,3 | awk -F'\t' '{printf "%-9s %-45s %s\n", $2, $3, $4}'

count() { printf '%s\n' "$ALL" | grep -c "^$1	" 2>/dev/null || true; }
n_upd=$(count UPDATED); n_cre=$(count CREATED); n_cur=$(count CURRENT)
n_skp=$(count SKIPPED); n_div=$(count DIVERGED); n_fail=$(count FAILED)
total=$(printf '%s\n' "$ALL" | grep -c . || true)

printf 'totals: %s updated, %s created, %s current, %s skipped, %s diverged, %s failed  (%s repos, %ss)\n' \
  "$n_upd" "$n_cre" "$n_cur" "$n_skp" "$n_div" "$n_fail" "$total" "$SECONDS"
echo "LOG: $LOG"

[ "$n_div" -gt 0 ] || [ "$n_fail" -gt 0 ] && exit 1
exit 0
