#!/usr/bin/env bash
# worktree-cleanup.sh — classify and remove linked git worktrees safely.
# Default is a dry run: it never deletes anything. Removal happens only for the
# exact paths passed to --remove, and each is re-checked before it goes.
# Written for bash 3.2 (macOS /bin/bash): no associative arrays, no mapfile.

set -uo pipefail

# A caller's inherited git routing/index environment can point our safety checks
# at a different repo, worktree, or index than the one we delete — a clean-looking
# status read from the wrong index would be a data-loss path. --repo is the only
# intended way to target a repo, so drop these before any git call.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY

REPO=""
PRUNE=0
FORCE=0
declare -a REMOVE=()
MODE="report"

usage() {
  cat <<'EOF'
usage: worktree-cleanup.sh [options]

Reports the linked worktrees of a repo, each classified KEEP / REMOVE / PRUNABLE.
By itself it deletes nothing. Pass --remove PATH to delete specific worktrees;
each named path is re-classified first and refused if it is not safe.

A worktree is kept (never a REMOVE candidate) when it has:
  - uncommitted changes (modified tracked files OR untracked files), or
  - commits not reachable from any remote-tracking branch (unpublished work), or
  - a lock.

options:
  -C, --repo PATH     repo to operate on (default: cwd's repo)
      --remove PATH    delete this worktree (repeatable). Refuses a KEEP/PRUNABLE
                       path unless --force. Only paths given here are ever touched.
      --prune          also `git worktree prune` — clears admin entries whose
                       directory is already gone from disk. Safe; deletes no work.
      --force          let --remove delete a worktree classified KEEP. Dangerous:
                       discards uncommitted changes and unpublished commits.
  -h, --help          this

exit: 0 ok; 1 a --remove target was refused or a removal failed; 2 bad usage.
EOF
}

# require a value that exists and is not itself a flag, so `--remove --prune`
# fails loudly instead of silently swallowing --prune as a path to delete.
need_val() {
  [ "$2" -ge 2 ] || { echo "option $1 needs a value" >&2; exit 2; }
  case "$3" in -?*) echo "option $1 needs a value, got the flag $3" >&2; exit 2 ;; esac
}
while [ $# -gt 0 ]; do
  case "$1" in
    -C|--repo)  need_val "$1" "$#" "${2:-}"; REPO="$2"; shift 2 ;;
    --remove)   need_val "$1" "$#" "${2:-}"; REMOVE+=("$2"); MODE="remove"; shift 2 ;;
    --prune)    PRUNE=1; shift ;;
    --force)    FORCE=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    -*)         echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)          echo "unexpected argument: $1 (paths go after --remove)" >&2; exit 2 ;;
  esac
done

[ -n "$REPO" ] || REPO="$PWD"
REPO="${REPO/#\~/$HOME}"
[ -d "$REPO" ] || { echo "not a directory: $REPO" >&2; exit 2; }
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repo: $REPO" >&2; exit 2; }

# Absolute, symlink-resolved path of the primary worktree — the one we must never
# offer to delete. `git worktree list` prints it first.
PRIMARY="$(git -C "$REPO" worktree list --porcelain | sed -n '1s/^worktree //p')"
HAS_REMOTE=0
[ -n "$(git -C "$REPO" remote)" ] && HAS_REMOTE=1

canon() {
  # resolve a path to its physical absolute form without requiring it to exist.
  # a relative path is resolved against $REPO, not the cwd, so a path copied from
  # the (repo-relative) dry-run table removes correctly from any working directory.
  # relative paths resolve against the primary worktree — the same anchor the
  # dry-run table prints paths against — so a path copied from that table removes
  # correctly no matter what --repo pointed at or which directory we run from.
  # (PRIMARY is unset only while it is itself being canonicalized; its input is
  # absolute then, so the base is never actually used.)
  local base="${PRIMARY:-$REPO}"
  local p="${1/#\~/$HOME}"
  case "$p" in /*) ;; *) p="$base/$p" ;; esac
  if [ -d "$p" ]; then ( cd "$p" && pwd -P ); return; fi
  # the leaf is gone (a prunable worktree) — resolve the existing parent through
  # symlinks and re-append the leaf, so it still matches git's -P stored path.
  local d b; d="$(dirname "$p")"; b="$(basename "$p")"
  if [ -d "$d" ]; then ( cd "$d" && printf '%s/%s\n' "$(pwd -P)" "$b" ); else echo "$p"; fi
}
PRIMARY="$(canon "$PRIMARY")"

# classify PATH -> prints "VERDICT<TAB>REASON". VERDICT in KEEP|REMOVE|PRUNABLE.
# Reads the porcelain block for that exact worktree path.
classify() {
  local target; target="$(canon "$1")"
  local block; block="$(git -C "$REPO" worktree list --porcelain \
    | awk -v t="$target" 'BEGIN{RS="";FS="\n"} { for(i=1;i<=NF;i++) if($i=="worktree "t){print;exit} }')"
  [ -n "$block" ] || { printf 'UNKNOWN\tnot a worktree of this repo\n'; return; }

  case "$block" in *$'\n'bare*|bare*) printf 'KEEP\tbare worktree\n'; return ;; esac
  if printf '%s\n' "$block" | grep -q '^locked'; then
    local why; why="$(printf '%s\n' "$block" | sed -n 's/^locked //p')"
    printf 'KEEP\tlocked%s\n' "${why:+: $why}"; return
  fi
  if printf '%s\n' "$block" | grep -q '^prunable'; then
    printf 'PRUNABLE\tworktree directory is gone\n'; return
  fi
  if [ "$target" = "$PRIMARY" ]; then printf 'KEEP\tprimary worktree\n'; return; fi

  # --untracked-files=all overrides a repo/global status.showUntrackedFiles=no,
  # under which an untracked-only worktree would otherwise read clean — and
  # `git worktree remove` honors that same config, so it would delete real work
  # with no --force. Never trust the user's status config for a deletion gate.
  local st; st="$(git -C "$target" status --porcelain --untracked-files=all 2>/dev/null)"; local rc=$?
  if [ $rc -ne 0 ]; then printf 'KEEP\tcannot read status — leaving it\n'; return; fi
  if [ -n "$st" ]; then
    local n; n="$(printf '%s\n' "$st" | grep -c .)"
    printf 'KEEP\tdirty (%s uncommitted)\n' "$n"; return
  fi

  local head; head="$(git -C "$target" rev-parse HEAD 2>/dev/null)"
  if [ "$HAS_REMOTE" -eq 0 ]; then
    printf 'KEEP\tno remote to verify against\n'; return
  fi
  local ahead; ahead="$(git -C "$REPO" rev-list --count "$head" --not --remotes 2>/dev/null)"
  if [ -z "$ahead" ]; then printf 'KEEP\tcould not compare to remotes\n'; return; fi
  if [ "$ahead" -gt 0 ]; then printf 'KEEP\t%s unpublished commit(s)\n' "$ahead"; return; fi

  # Gitignored working files (a local .env, a database, credentials, build output)
  # are backed up nowhere and `git worktree remove` deletes them. They are not a
  # tracked change, so git calls the tree clean — but we keep it and require an
  # explicit --force, so an irreplaceable .env is never dropped by a plain --remove.
  # Tracked and untracked are already clean here, so any '!!' line is ignored.
  # Capture first, then grep: piping git straight into `grep -q` lets grep close on
  # its first match, and git dying of SIGPIPE under `pipefail` would flip this test
  # to false and silently mislabel the worktree clean.
  local ign; ign="$(git -C "$target" status --porcelain --ignored=matching --untracked-files=all 2>/dev/null)"
  if printf '%s\n' "$ign" | grep -q '^!!'; then
    printf 'KEEP\thas ignored local files (e.g. .env/build); --force to discard\n'; return
  fi
  printf 'REMOVE\tclean, fully published\n'
}

# classify() returns "VERDICT<TAB>REASON"; both loops decode it through here so
# the contract lives in one place. Sets the globals V and R.
split_vr() { V="${1%%$'\t'*}"; R="${1#*$'\t'}"; }
ROW_FMT='%-9s  %-45s  %s\n'   # header and every row share these column widths

if [ "$MODE" = "report" ]; then
  echo "=== WORKTREE-CLEANUP (dry run — nothing deleted) ==="
  echo "repo: $PRIMARY"
  shown=0
  while IFS= read -r wt; do
    [ "$(canon "$wt")" = "$PRIMARY" ] && continue
    if [ "$shown" -eq 0 ]; then printf "$ROW_FMT" VERDICT PATH REASON; shown=1; fi
    split_vr "$(classify "$wt")"
    rel="${wt#"$PRIMARY"/}"
    printf "$ROW_FMT" "$V" "$rel" "$R"
  done < <(git -C "$REPO" worktree list --porcelain | sed -n 's/^worktree //p')
  [ "$shown" -eq 0 ] && echo "(no linked worktrees — only the primary one exists)"
  prune_rc=0
  if [ "$PRUNE" -eq 1 ]; then
    echo "--- pruning missing worktree entries ---"
    git -C "$REPO" worktree prune -v || { echo "prune failed"; prune_rc=1; }
  fi
  echo "note: \"published\" is checked against local remote-tracking refs — run \`git fetch\` first for an up-to-date result."
  echo "=== next: worktree-cleanup.sh --remove <PATH> for each one you approve ==="
  exit $prune_rc
fi

# ---- remove mode: only the paths passed in --remove, each re-checked ----
ERR="$(mktemp "${TMPDIR:-/tmp}/worktree-cleanup.XXXXXX")"
trap 'rm -f "$ERR"' EXIT
rc_all=0
for path in "${REMOVE[@]}"; do
  # Canonicalize once and gate AND delete the same path. classify judged the
  # canonical target, so removal must hand git that exact path — not the raw
  # argument, which for a ~- or relative value can resolve somewhere else.
  cpath="$(canon "$path")"
  if [ "$cpath" = "$PRIMARY" ]; then
    echo "REFUSED   $path — primary worktree, never removable (not even with --force)"; rc_all=1; continue
  fi
  split_vr "$(classify "$cpath")"
  case "$V" in
    REMOVE)
      if git -C "$REPO" worktree remove "$cpath" 2>"$ERR"; then
        echo "REMOVED   $path"
      else
        echo "FAILED    $path — $(cat "$ERR")"; rc_all=1
      fi
      ;;
    PRUNABLE)
      echo "SKIPPED   $path — $R (use --prune to clear the stale entry)"; rc_all=1
      ;;
    UNKNOWN)
      echo "SKIPPED   $path — $R"; rc_all=1
      ;;
    KEEP)
      if [ "$FORCE" -eq 1 ]; then
        # A locked worktree needs a second --force from git; forward it so the
        # documented "--force removes a KEEP" holds for locks too.
        force_args=(--force); case "$R" in locked*) force_args=(--force --force) ;; esac
        if git -C "$REPO" worktree remove "${force_args[@]}" "$cpath" 2>"$ERR"; then
          echo "FORCED    $path — was: $R"
        else
          echo "FAILED    $path — $(cat "$ERR")"; rc_all=1
        fi
      else
        echo "REFUSED   $path — $R (pass --force only if you accept losing it)"; rc_all=1
      fi
      ;;
  esac
done
if [ "$PRUNE" -eq 1 ]; then
  git -C "$REPO" worktree prune -v || { echo "prune failed"; rc_all=1; }
fi
exit $rc_all
