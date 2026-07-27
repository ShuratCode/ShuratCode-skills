#!/usr/bin/env bash
# upgrade-all.sh — runs every routine local upgrade and prints ONE compact summary.
#
# Design goal: do all the noisy work here so the calling skill only has to read a
# short structured summary (token savings). Verbose per-step output is written to a
# log file; only a concise SUMMARY block is printed to stdout.
#
# Output contract (stdout):
#   A single block delimited by "=== UPGRADE-ALL SUMMARY ===" / "=== END SUMMARY ==="
#   with one "key: STATUS — detail" line per component, plus a LOG: path line.
#   STATUS is one of: UPGRADED | CURRENT | SKIPPED | FAILED

set -u

LOG="${TMPDIR:-/tmp}/upgrade-all-$(date +%Y%m%d-%H%M%S).log"
: > "$LOG"

# Accumulators for the summary (parallel arrays kept simple for portability).
SUMMARY=""

add() { # name  status  detail
  SUMMARY+="$1: $2 — $3"$'\n'
}

logrun() { # description  command...
  local desc="$1"; shift
  {
    echo "### $desc"
    echo "\$ $*"
  } >> "$LOG"
  "$@" >> "$LOG" 2>&1
  local rc=$?
  echo "(exit $rc)" >> "$LOG"
  return $rc
}

tail_log() { tail -n 8 "$LOG" | sed 's/^/    /'; }

# ---------------------------------------------------------------------------
# 1) Homebrew
# ---------------------------------------------------------------------------
if command -v brew >/dev/null 2>&1; then
  if logrun "brew update" brew update; then
    n_formula=$(brew outdated --formula 2>/dev/null | wc -l | tr -d ' ')
    n_cask=$(brew outdated --cask 2>/dev/null | wc -l | tr -d ' ')
    fail=0
    logrun "brew upgrade" brew upgrade || fail=1
    logrun "brew upgrade --cask" brew upgrade --cask || fail=1
    logrun "brew cleanup --prune=all" brew cleanup --prune=all || true
    logrun "brew autoremove" brew autoremove || true
    if [ "$fail" -ne 0 ]; then
      add "homebrew" "FAILED" "see log; outdated before: ${n_formula} formulae / ${n_cask} casks"
    elif [ "${n_formula}" = "0" ] && [ "${n_cask}" = "0" ]; then
      add "homebrew" "CURRENT" "no outdated formulae or casks"
    else
      add "homebrew" "UPGRADED" "${n_formula} formulae, ${n_cask} casks"
    fi
  else
    add "homebrew" "FAILED" "brew update failed"
  fi
else
  add "homebrew" "SKIPPED" "brew not installed"
fi

# ---------------------------------------------------------------------------
# 2) gstack (inline git-install upgrade; non-interactive)
# ---------------------------------------------------------------------------
GS_DIR=""
for d in "$HOME/.claude/skills/gstack" "$HOME/.gstack/repos/gstack"; do
  [ -d "$d/.git" ] && { GS_DIR="$d"; break; }
done
if [ -n "$GS_DIR" ]; then
  GS_OLD=$(cat "$GS_DIR/VERSION" 2>/dev/null || echo "unknown")
  (
    cd "$GS_DIR" || exit 1
    echo "### gstack upgrade in $GS_DIR" >> "$LOG"
    git stash >> "$LOG" 2>&1 || true
    git fetch origin >> "$LOG" 2>&1
    git reset --hard origin/main >> "$LOG" 2>&1
    ./setup >> "$LOG" 2>&1
  )
  GS_RC=$?
  GS_NEW=$(cat "$GS_DIR/VERSION" 2>/dev/null || echo "unknown")
  # Run any pending migrations (idempotent), best-effort.
  MIG="$GS_DIR/gstack-upgrade/migrations"
  if [ "$GS_RC" -eq 0 ] && [ -d "$MIG" ] && [ "$GS_OLD" != "unknown" ]; then
    for m in $(find "$MIG" -maxdepth 1 -name 'v*.sh' -type f 2>/dev/null | sort -V); do
      mv="$(basename "$m" .sh | sed 's/^v//')"
      if [ "$(printf '%s\n%s' "$GS_OLD" "$mv" | sort -V | head -1)" = "$GS_OLD" ] && [ "$GS_OLD" != "$mv" ]; then
        echo "### migration $mv" >> "$LOG"
        bash "$m" >> "$LOG" 2>&1 || echo "  migration $mv non-fatal error" >> "$LOG"
      fi
    done
    # Clear update-check cache so the next skill run doesn't re-prompt.
    mkdir -p "$HOME/.gstack"
    echo "$GS_OLD" > "$HOME/.gstack/just-upgraded-from"
    rm -f "$HOME/.gstack/last-update-check" "$HOME/.gstack/update-snoozed"
  fi
  if [ "$GS_RC" -ne 0 ]; then
    add "gstack" "FAILED" "git/setup failed (was $GS_OLD)"
  elif [ "$GS_OLD" = "$GS_NEW" ]; then
    add "gstack" "CURRENT" "v$GS_NEW"
  else
    add "gstack" "UPGRADED" "v$GS_OLD → v$GS_NEW"
  fi
else
  add "gstack" "SKIPPED" "no git install found"
fi

# ---------------------------------------------------------------------------
# 3-5) Claude plugins (lattice, aws-core, sparkpilot)
# ---------------------------------------------------------------------------
if command -v claude >/dev/null 2>&1; then
  logrun "claude plugins marketplace update" claude plugins marketplace update || true
  PLUGINS=$(claude plugins list 2>/dev/null)
  upgrade_plugin() { # display  qualified  bare
    local name="$1" qualified="$2" bare="$3" ref=""
    if printf '%s' "$PLUGINS" | grep -q "$qualified"; then
      ref="$qualified"
    elif printf '%s' "$PLUGINS" | grep -q "$bare"; then
      ref="$bare"
    fi
    if [ -z "$ref" ]; then
      add "$name" "SKIPPED" "not installed"
      return
    fi
    local out rc
    out=$(claude plugins update "$ref" 2>&1); rc=$?
    echo "### claude plugins update $ref" >> "$LOG"
    printf '%s\n' "$out" >> "$LOG"
    if [ "$rc" -ne 0 ]; then
      add "$name" "FAILED" "update $ref failed"
    elif printf '%s' "$out" | grep -qiE "already|up to date|up-to-date|no update"; then
      add "$name" "CURRENT" "$ref"
    else
      add "$name" "UPGRADED" "$ref"
    fi
  }
  upgrade_plugin "lattice"    "lattice@lattice"                  "lattice"
  upgrade_plugin "aws-core"   "aws-core@claude-plugins-official" "aws-core"
  upgrade_plugin "sparkpilot" "sparkpilot@vi-technologies"       "sparkpilot"
else
  add "lattice" "SKIPPED" "claude CLI not found"
  add "aws-core" "SKIPPED" "claude CLI not found"
  add "sparkpilot" "SKIPPED" "claude CLI not found"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "=== UPGRADE-ALL SUMMARY ==="
printf '%s' "$SUMMARY"
echo "LOG: $LOG"
# If anything failed, surface the tail of the log to aid diagnosis.
if printf '%s' "$SUMMARY" | grep -q "FAILED"; then
  echo "--- last log lines (failures present) ---"
  tail_log
fi
echo "=== END SUMMARY ==="
