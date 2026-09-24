#!/usr/bin/env bash

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HERE/../scripts"
PASS=0; FAIL=0
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

G() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
ok()  { printf '  ok   %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL %s\n       want %s / got %s\n' "$1" "$2" "$3"; FAIL=$((FAIL + 1)); }
key() { grep "^$2:" "$1" | head -1 | sed "s/^$2: *//"; }
want() {
  local got; got="$(key "$1" "$2")"
  [ "$got" = "$3" ] && ok "$4 — $2=$3" || bad "$4" "$2=$3" "$2=$got"
}

BIN="$TMP/bin"
mkdir -p "$BIN"
cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "pr" ] && [ "$2" = "view" ] || { echo "stub gh: unexpected: $*" >&2; exit 9; }
printf '{"number":42,"title":"t","url":"https://github.com/acme/widgets/pull/42","state":"OPEN","isCrossRepository":false,"headRefName":"feature","headRefOid":"","baseRefName":"main"}\n'
EOF
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"

ORIGIN="$TMP/origin"
mkdir -p "$ORIGIN"
G -C "$ORIGIN" init -q -b main
echo one > "$ORIGIN/app.txt"
echo x > "$ORIGIN/other.txt"
G -C "$ORIGIN" add -A && G -C "$ORIGIN" commit -q -m base

commit_on() { # branch file content
  G -C "$ORIGIN" checkout -q "$1"
  echo "$3" > "$ORIGIN/$2"
  G -C "$ORIGIN" add -A && G -C "$ORIGIN" commit -q -m "$2"
}
publish() { G -C "$ORIGIN" update-ref refs/pull/42/head "$(G -C "$ORIGIN" rev-parse feature)"; }

G -C "$ORIGIN" checkout -q -b feature
echo two > "$ORIGIN/app.txt"
echo body > "$ORIGIN/added.txt"
G -C "$ORIGIN" add -A && G -C "$ORIGIN" commit -q -m "pr work"
publish
G -C "$ORIGIN" checkout -q main

WT="$TMP/wt"
git clone -q "$ORIGIN" "$WT"
G -C "$WT" remote set-url origin "git@github.com:acme/widgets.git"
G -C "$WT" config --local "url.$ORIGIN.insteadOf" "git@github.com:acme/widgets.git"
echo ".fresh-review/" > "$WT/.gitignore"
G -C "$WT" add .gitignore && G -C "$WT" commit -q -m ignore

review() { # label [--delta]
  (cd "$WT" && bash "$SCRIPTS/fr-preflight.sh" --pr 42 "${@:2}" > "$TMP/$1.pf" 2>&1)
  RD="$(key "$TMP/$1.pf" RUN_DIR)"
  (cd "$WT" && bash "$SCRIPTS/fr-pr-resolve.sh" "$RD" > "$TMP/$1.pr" 2>&1)
  (cd "$WT" && bash "$SCRIPTS/fr-delta.sh" "$RD" > "$TMP/$1.out" 2>&1)
}
record() { # verdict blockers-json [coverage]
  printf '%s\n' "$2" > "$RD/blockers.json"
  (cd "$WT" && bash "$SCRIPTS/fr-review-record.sh" "$RD" "$1" "${3:-full}" > "$TMP/record.out" 2>&1)
}
RECORD_FILE() { echo "$WT/.git/fresh-review/reviews/pr-42.json"; }
BLOCKER='[{"severity":"HIGH","file":"app.txt","line":1,"category":"correctness","problem":"value is wrong","fix":"use three","sources":["lattice"]}]'
restore() { (cd "$WT" && bash "$SCRIPTS/fr-restore.sh" "$RD" >/dev/null 2>&1); }
names() { (cd "$WT" && $(key "$TMP/$1.out" DIFF_CMD) --name-only | sort | tr '\n' ' '); }

printf '\n\033[1mfresh-review delta re-review\033[0m\n'

(cd "$WT" && bash "$SCRIPTS/fr-preflight.sh" --delta >/dev/null 2>&1); RC=$?
[ "$RC" -eq 2 ] && ok "--delta without --pr is rejected" || bad "--delta alone" "exit 2" "exit $RC"

review first --delta
want "$TMP/first.pf" DELTA_REQUESTED 1 "preflight --delta"
want "$TMP/first.pr" REVIEW_KEY pr-42 "the review key names the PR"
want "$TMP/first.out" DELTA full "no earlier review"
want "$TMP/first.out" DELTA_REASON no_prior_review "no earlier review"
FIRST_RUN="$(key "$TMP/first.pf" RUN_DIR)"; FIRST_RUN="${FIRST_RUN##*/}"
record REQUEST-CHANGES "$BLOCKER"
want "$TMP/record.out" RECORD written "a finished review is recorded"
want "$TMP/record.out" BLOCKERS 1 "a finished review is recorded"
OLD_HEAD="$(G -C "$ORIGIN" rev-parse feature)"
[ "$(G -C "$WT" rev-parse refs/fresh-review/reviewed/pr-42/head)" = "$OLD_HEAD" ] \
  && ok "the reviewed head is pinned by a ref" || bad "reviewed ref" "$OLD_HEAD" "missing"
restore

review same --delta
want "$TMP/same.out" DELTA none "no push since the review"
want "$TMP/same.out" DELTA_REASON no_new_commits "no push since the review"
want "$TMP/same.out" PRIOR_BLOCKERS 1 "no push since the review"
restore

cp "$(RECORD_FILE)" "$TMP/record.bak"
G -C "$WT" update-ref refs/fresh-review/reviewed/pr-42/head "$(G -C "$WT" rev-parse origin/main)"
review mismatch --delta
want "$TMP/mismatch.out" DELTA full "the refs and the record disagree"
want "$TMP/mismatch.out" DELTA_REASON record_mismatch "the refs and the record disagree"
restore
G -C "$WT" update-ref refs/fresh-review/reviewed/pr-42/head "$OLD_HEAD"

echo '{not json' > "$(RECORD_FILE)"
review corrupt --delta
want "$TMP/corrupt.out" DELTA full "a corrupt record"
want "$TMP/corrupt.out" DELTA_REASON record_invalid "a corrupt record"
want "$TMP/corrupt.out" PRIOR_REVIEW none "a corrupt record"
restore
cp "$TMP/record.bak" "$(RECORD_FILE)"

python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); r["coverage"]="reduced"; json.dump(r,open(sys.argv[1],"w"))' "$(RECORD_FILE)"
review reduced --delta
want "$TMP/reduced.out" DELTA full "the earlier review lost a lens"
want "$TMP/reduced.out" DELTA_REASON prior_reduced_coverage "the earlier review lost a lens"
restore
cp "$TMP/record.bak" "$(RECORD_FILE)"

review plain
want "$TMP/plain.out" DELTA off "a plain --pr run"
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["coverage"]=="full"' "$(RECORD_FILE)" \
  && ok "the record stores its coverage" || bad "record coverage" "full" "$(cat "$(RECORD_FILE)")"
want "$TMP/plain.out" PRIOR_REVIEW "$FIRST_RUN" "a plain --pr run still reports the earlier review"
restore

commit_on feature added.txt fixed
commit_on feature fix.txt new
publish
review ff --delta
want "$TMP/ff.out" DELTA applied "fixes pushed on top"
want "$TMP/ff.out" DELTA_KIND fast_forward "fixes pushed on top"
[ "$(names ff)" = "added.txt fix.txt " ] && ok "the delta holds only the fixes" \
  || bad "fast-forward delta files" "added.txt fix.txt" "$(names ff)"
SRC="$(key "$TMP/ff.pr" SOURCE_ROOT)"
[ "$(cat "$SRC/app.txt")" = two ] && [ -f "$SRC/fix.txt" ] && ok "SOURCE_ROOT still holds the PR head's files" \
  || bad "SOURCE_ROOT" "PR head files" "$(ls "$SRC")"
BASE="$(key "$TMP/ff.out" DIFF_BASE)"
[ "$(G -C "$SRC" merge-base "$BASE" HEAD)" = "$BASE" ] \
  && ok "the delta base is an ancestor of the worktree HEAD (codex --base, /review)" \
  || bad "delta ancestry" "$BASE" "$(G -C "$SRC" merge-base "$BASE" HEAD)"
[ -z "$(G -C "$SRC" status --porcelain)" ] && ok "moving the worktree leaves it clean" \
  || bad "worktree status" "clean" "$(G -C "$SRC" status --porcelain)"
grep -q "B1. HIGH app.txt:1 \[correctness\] value is wrong" "$RD/delta/prior-blockers.md" \
  && ok "the earlier blockers are handed on" || bad "prior blockers" "B1 line" "$(cat "$RD/delta/prior-blockers.md")"
(cd "$WT" && bash "$SCRIPTS/fr-packet.sh" "$RD" > "$TMP/ff.packet" 2>&1)
want "$TMP/ff.packet" FILES 2 "the packet is the delta"
grep -qx "DELTA=since-last-review" "$RD/packet/scope.txt" && ok "scope.txt marks the delta" \
  || bad "scope.txt" "DELTA=since-last-review" "$(cat "$RD/packet/scope.txt")"
record APPROVE-WITH-COMMENTS "$BLOCKER"
NEW_HEAD="$(G -C "$ORIGIN" rev-parse feature)"
[ "$(G -C "$WT" rev-parse refs/fresh-review/reviewed/pr-42/head)" = "$NEW_HEAD" ] \
  && ok "a re-review moves the record to the new head" || bad "record head" "$NEW_HEAD" "old"
restore

commit_on feature scratch.txt tmp
G -C "$ORIGIN" rm -q scratch.txt && G -C "$ORIGIN" commit -q -m revert
publish
review revert --delta
want "$TMP/revert.out" DELTA none "a push that nets to nothing"
want "$TMP/revert.out" DELTA_REASON no_net_change "a push that nets to nothing"
restore

commit_on main other.txt y
G -C "$ORIGIN" checkout -q feature
G -C "$ORIGIN" rebase -q main
publish
review rebaseblocked --delta
want "$TMP/rebaseblocked.out" DELTA full "a rebase with nothing new, and open blockers"
want "$TMP/rebaseblocked.out" DELTA_REASON rebased_with_blockers "a rebase with nothing new, and open blockers"
restore

commit_on feature fix2.txt new
publish
review rebased --delta
want "$TMP/rebased.out" DELTA applied "rebased onto a newer main, with a fix"
want "$TMP/rebased.out" DELTA_KIND rebased "rebased onto a newer main, with a fix"
[ "$(names rebased)" = "fix2.txt " ] && ok "main's own changes stay out of the delta" \
  || bad "rebased delta files" "fix2.txt" "$(names rebased)"
echo "RISK='high'" >> "$RD/state.env"
record APPROVE '[]'
restore

commit_on feature low.txt small
publish
review riskfloor --delta
want "$TMP/riskfloor.out" PRIOR_RISK high "a high-risk earlier review"
(cd "$WT" && bash "$SCRIPTS/fr-packet.sh" "$RD" > "$TMP/riskfloor.packet" 2>&1)
want "$TMP/riskfloor.packet" RISK high "a small delta keeps the earlier high risk"
record APPROVE '[]'
restore

G -C "$WT" fetch -q origin main
OLD_BASE="$(G -C "$WT" rev-parse origin/main~1)"
CUR_BASE="$(G -C "$WT" rev-parse refs/fresh-review/reviewed/pr-42/base)"
cp "$(RECORD_FILE)" "$TMP/record.bak"
python3 - "$(RECORD_FILE)" "$OLD_BASE" <<'PY2'
import json, sys
r = json.load(open(sys.argv[1])); r["base"] = sys.argv[2]; json.dump(r, open(sys.argv[1], "w"))
PY2
G -C "$WT" update-ref refs/fresh-review/reviewed/pr-42/base "$OLD_BASE"
review retarget --delta
want "$TMP/retarget.out" DELTA none "same head, moved base"
want "$TMP/retarget.out" DELTA_REASON rebase_only "same head, moved base is not no_new_commits"
restore
cp "$TMP/record.bak" "$(RECORD_FILE)"
G -C "$WT" update-ref refs/fresh-review/reviewed/pr-42/base "$CUR_BASE"

commit_on main other.txt z
G -C "$ORIGIN" checkout -q feature
G -C "$ORIGIN" rebase -q main
publish
review rebaseonly --delta
want "$TMP/rebaseonly.out" DELTA none "a rebase with no new changes"
want "$TMP/rebaseonly.out" DELTA_REASON rebase_only "a rebase with no new changes"
restore

commit_on main app.txt three
G -C "$ORIGIN" checkout -q -B feature main
printf 'four\n' > "$ORIGIN/app.txt"
printf 'fixed\n' > "$ORIGIN/added.txt"
printf 'new\n' > "$ORIGIN/fix.txt"
printf 'new\n' > "$ORIGIN/fix2.txt"
G -C "$ORIGIN" add -A && G -C "$ORIGIN" commit -q -m "rebased with conflict"
publish
G -C "$ORIGIN" checkout -q main
review conflict --delta
want "$TMP/conflict.out" DELTA full "the old PR no longer applies to the new base"
want "$TMP/conflict.out" DELTA_REASON replay_conflict "the old PR no longer applies to the new base"
restore

review junk
record APPROVE '{"a":1}'
want "$TMP/record.out" REASON bad_blockers "blockers must be a JSON array"
record APPROVE '[{"file":"a"}]'
want "$TMP/record.out" REASON bad_blockers "each blocker needs every field"
record APPROVE '[]' partial
want "$TMP/record.out" REASON bad_coverage "coverage is full or reduced"
record LGTM '[]'
want "$TMP/record.out" REASON bad_verdict "only pr-remote verdicts are recorded"
restore

[ -z "$(G -C "$WT" status --porcelain)" ] && ok "the user's checkout is untouched" \
  || bad "checkout" "clean" "$(G -C "$WT" status --porcelain)"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
