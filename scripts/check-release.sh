#!/usr/bin/env bash
# check-release.sh [base-ref] — fail when a plugin's files changed without a
# version bump.
#
# `claude plugins update` extracts into a cache keyed on the `version` in
# plugins/<name>/.claude-plugin/plugin.json. If that string is unchanged, the
# updater compares equal, reports CURRENT, and leaves the stale cache in place —
# so merged code never reaches a single machine. That is invisible to
# `claude plugin validate`, which checks manifest shape, not delivery.
#
# This happened twice (PRs #8 and #9, both fresh-review) before anyone noticed.
#
# Compares the working tree against the merge-base with <base-ref> (default
# origin/main), so it is equally usable as a pre-push check and as CI.

set -uo pipefail
cd "$(dirname "$0")/.."

BASE="${1:-${BASE_REF:-origin/main}}"

FAIL=0
err()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; FAIL=1; }
ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
skip() { printf '  \033[90mskip\033[0m  %s\n' "$*"; }
head_(){ printf '\n\033[1m%s\033[0m\n' "$*"; }

command -v python3 >/dev/null || { echo "python3 required"; exit 2; }

git rev-parse --verify -q "$BASE" >/dev/null || BASE=main
git rev-parse --verify -q "$BASE" >/dev/null || {
  echo "check-release: cannot resolve a base ref (tried '$1' and 'main')" >&2
  exit 2
}
MB=$(git merge-base "$BASE" HEAD) || exit 2

head_ "Release gate (base: $BASE @ ${MB:0:8})"

# Untracked files are unioned in: `git diff` cannot see a brand-new skill file,
# and adding one to a plugin needs a bump just as much as editing one.
CHANGED=$( { git diff --name-only "$MB" -- .; git ls-files --others --exclude-standard; } | sort -u)
[ -n "$CHANGED" ] || { skip "no changes against $BASE"; echo; echo "Nothing to gate."; exit 0; }

version_now() {  # path
  [ -f "$1" ] || { echo ""; return; }
  python3 -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("version",""))
except Exception: print("")' "$1"
}

version_base() { # path
  git show "$MB:$1" 2>/dev/null | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("version",""))
except Exception: print("")' 2>/dev/null
}

# Greater-than, not merely different: a downgrade also changes the string but
# reinstalls an older cache entry.
semver_gt() { # new old
  python3 -c '
import sys
def parse(v):
    core = v.split("+")[0].split("-")[0]
    return tuple(int(x) for x in core.split("."))
try:
    sys.exit(0 if parse(sys.argv[1]) > parse(sys.argv[2]) else 1)
except Exception:
    sys.exit(2)' "$1" "$2"
}

BUMPED_ANY=0
TOUCHED_ANY=0

# tests/ ships in the cache but cannot change installed behavior. Forcing a
# release for a test edit is the fastest way to train everyone to ignore this
# gate, so test-only changes are exempt — matching how changesets and
# semantic-release treat them.
for d in plugins/*/; do
  name=$(basename "$d")
  touched=$(printf '%s\n' "$CHANGED" | grep "^plugins/$name/" | grep -cv "^plugins/$name/tests/" || true)
  if [ "$touched" -eq 0 ]; then
    if printf '%s\n' "$CHANGED" | grep -q "^plugins/$name/tests/"; then
      skip "$name: tests-only change — no bump required"
      TOUCHED_ANY=1
    fi
    continue
  fi
  TOUCHED_ANY=1

  manifest="plugins/$name/.claude-plugin/plugin.json"
  new=$(version_now "$manifest")
  old=$(version_base "$manifest")

  if [ -z "$old" ]; then
    ok "$name: new plugin at $new — no bump required ($touched file(s))"
    BUMPED_ANY=1
    continue
  fi
  if [ -z "$new" ]; then
    err "$name: $touched file(s) changed but plugin.json has no 'version'. Without it the commit SHA becomes the version — pick one and be explicit."
    continue
  fi
  if [ "$new" = "$old" ]; then
    err "$name: $touched file(s) changed but version is still $new. \`claude plugins update\` will report CURRENT and ship nothing — bump $manifest."
    continue
  fi
  if semver_gt "$new" "$old"; then
    ok "$name: $old -> $new ($touched file(s))"
    BUMPED_ANY=1
  else
    err "$name: version went $old -> $new, which is not an increase. Users on $old would never receive it."
  fi
done

if [ "$TOUCHED_ANY" -eq 0 ]; then
  skip "no plugin files changed"
elif [ "$BUMPED_ANY" -eq 1 ]; then
  mp=".claude-plugin/marketplace.json"
  mnew=$(version_now "$mp"); mold=$(version_base "$mp")
  if [ -z "$mold" ] || [ -z "$mnew" ]; then
    skip "marketplace.json has no version to compare"
  elif [ "$mnew" = "$mold" ]; then
    err "a plugin was bumped but $mp is still $mnew — bump it too (repo convention)"
  elif semver_gt "$mnew" "$mold"; then
    ok "marketplace: $mold -> $mnew"
  else
    err "marketplace version went $mold -> $mnew, which is not an increase"
  fi

  if printf '%s\n' "$CHANGED" | grep -qx "CHANGELOG.md"; then
    ok "CHANGELOG.md updated"
  else
    err "a plugin was bumped but CHANGELOG.md is untouched — every release in this repo documents itself"
  fi
fi

# Setting version in both places lets a stale marketplace entry mask a mismatch;
# Claude Code always uses the plugin.json value, silently.
head_ "Manifest hygiene"
python3 - <<'PY'
import json, sys
mp = json.load(open(".claude-plugin/marketplace.json"))
bad = [p["name"] for p in mp.get("plugins", []) if "version" in p]
if bad:
    print(f"  \033[31mFAIL\033[0m  marketplace entries carry a 'version' key: {', '.join(bad)}. "
          f"Claude Code always uses plugin.json's value, so this can only ever drift.")
    sys.exit(1)
print("  \033[32mok\033[0m    no version keys duplicated into marketplace entries")
PY
[ $? -eq 0 ] || FAIL=1

echo
if [ "$FAIL" -eq 1 ]; then
  printf '\033[31mRelease gate failed.\033[0m A merge that trips this ships nothing.\n'
  exit 1
fi
printf '\033[32mRelease gate passed.\033[0m\n'
