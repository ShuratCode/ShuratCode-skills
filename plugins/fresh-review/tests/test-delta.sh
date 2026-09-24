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
choose() { # label choice
  (cd "$WT" && bash "$SCRIPTS/fr-delta.sh" "$RD" --choice "$2" > "$TMP/$1.out" 2>&1)
}
at_pr_head() { # label
  [ "$(G -C "$(key "$TMP/$1.pr" SOURCE_ROOT)" rev-parse HEAD)" = "$(key "$TMP/$1.pr" PR_HEAD)" ]
}

printf '\n\033[1mfresh-review delta re-review\033[0m\n'

(cd "$WT" && bash "$SCRIPTS/fr-preflight.sh" --delta >/dev/null 2>&1); RC=$?
[ "$RC" -eq 2 ] && ok "--delta without --pr is rejected" || bad "--delta alone" "exit 2" "exit $RC"

MANIFEST_VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$HERE/../.claude-plugin/plugin.json")"
mkdir -p "$TMP/home/.claude/plugins/cache/ShuratCode-skills/fresh-review/99.0.0" \
  "$TMP/home/.claude/plugins/cache/ShuratCode-skills/fresh-review/0.1.0"
(cd "$WT" && HOME="$TMP/home" bash "$SCRIPTS/fr-preflight.sh" --pr 42 > "$TMP/stale.pf" 2>&1)
want "$TMP/stale.pf" PLUGIN_VERSION "$MANIFEST_VERSION" "preflight names the version of the copy it runs from"
want "$TMP/stale.pf" PLUGIN_INSTALLED 99.0.0 "preflight names the newest installed version"
want "$TMP/stale.pf" PLUGIN_STALE yes "a session copy older than the install is flagged"
mkdir -p "$TMP/home2"
(cd "$WT" && HOME="$TMP/home2" bash "$SCRIPTS/fr-preflight.sh" --pr 42 > "$TMP/fresh.pf" 2>&1)
want "$TMP/fresh.pf" PLUGIN_STALE no "no install to compare against"
grep -qx "FR_VERSION='$MANIFEST_VERSION'" "$(key "$TMP/fresh.pf" STATE)" \
  && ok "state.env carries the running version" || bad "state FR_VERSION" "$MANIFEST_VERSION" "missing"

review first --delta
want "$TMP/first.pf" DELTA_REQUESTED 1 "preflight --delta"
want "$TMP/first.pr" REVIEW_KEY pr-42 "the review key names the PR"
want "$TMP/first.out" DELTA ask "an explicit --delta with no earlier review asks"
want "$TMP/first.out" DELTA_REASON no_prior_review "no earlier review"
choose firstfull full
want "$TMP/firstfull.out" DELTA full "the user chose a full review"
want "$TMP/firstfull.out" DELTA_REASON no_prior_review "the user chose a full review"
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
want "$TMP/reduced.out" DELTA none "a reduced earlier review with no push since"
want "$TMP/reduced.out" PRIOR_COVERAGE reduced "a reduced earlier review with no push since"
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
python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); r["coverage"]="reduced"; json.dump(r,open(sys.argv[1],"w"))' "$(RECORD_FILE)"
review ffreduced --delta
want "$TMP/ffreduced.out" DELTA ask "the earlier review lost a lens"
want "$TMP/ffreduced.out" DELTA_REASON prior_reduced_coverage "the earlier review lost a lens"
at_pr_head ffreduced && ok "asking leaves the worktree at the PR head" \
  || bad "worktree while asking" "PR head" "moved"
choose ffreducedyes delta
want "$TMP/ffreducedyes.out" DELTA applied "the user accepted the gap"
want "$TMP/ffreducedyes.out" PRIOR_COVERAGE reduced "the user accepted the gap"
grep -qx "DELTA_PRIOR_COVERAGE='reduced'" "$RD/state.env" && ok "the gap is kept for the coverage line" \
  || bad "state DELTA_PRIOR_COVERAGE" reduced "missing"
restore
review ffreducedno --delta
choose ffreducedfull full
want "$TMP/ffreducedfull.out" DELTA full "the user chose a full review over the gap"
want "$TMP/ffreducedfull.out" DELTA_REASON prior_reduced_coverage "the user chose a full review over the gap"
at_pr_head ffreducedno && ok "a full review stays on the PR head" || bad "worktree on full" "PR head" "moved"
restore
cp "$TMP/record.bak" "$(RECORD_FILE)"

review ff --delta
want "$TMP/ff.out" DELTA_SOURCE record "a recorded review is the source"
want "$TMP/ff.out" PRIOR_ARCH_GATE none "the first review recorded no architecture approval"
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
echo "ARCH_GATE='approved'" >> "$RD/state.env"
printf '### D1 — the ff decision\n' > "$RD/raw/architecture.md"
record APPROVE-WITH-COMMENTS "$BLOCKER"
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["arch_gate"]=="approved"' "$(RECORD_FILE)" \
  && ok "the record keeps the approved architecture" || bad "record arch_gate" approved "$(cat "$(RECORD_FILE)")"
grep -q "the ff decision" "$WT/.git/fresh-review/reviews/pr-42.architecture.md" \
  && ok "the approved decisions are kept next to the record" || bad "architecture file" "D1" "missing"
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
want "$TMP/rebased.out" PRIOR_ARCH_GATE approved "the earlier approval is carried to the re-review"
grep -q "the ff decision" "$RD/delta/prior-architecture.md" \
  && ok "Pass D gets the approved decisions" || bad "prior-architecture.md" "D1" "missing"
echo "RISK='high'" >> "$RD/state.env"
echo "ARCH_GATE='carried'" >> "$RD/state.env"
printf '### D1 — the ff decision, extended\n' > "$RD/raw/architecture.md"
record APPROVE '[]'
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["arch_gate"]=="approved"' "$(RECORD_FILE)" \
  && ok "a carried approval stays approved" || bad "record arch_gate after carry" approved "$(cat "$(RECORD_FILE)")"
[ "$(grep -c '^### D1' "$WT/.git/fresh-review/reviews/pr-42.architecture.md")" = 1 ] \
  && grep -q "^### D1 — the ff decision$" "$WT/.git/fresh-review/reviews/pr-42.architecture.md" \
  && ok "a carried approval keeps the earlier decisions once" || bad "architecture file after carry" \
  "one D1" "$(cat "$WT/.git/fresh-review/reviews/pr-42.architecture.md")"
restore

commit_on feature low.txt small
publish
review riskfloor --delta
want "$TMP/riskfloor.out" PRIOR_RISK high "a high-risk earlier review"
(cd "$WT" && bash "$SCRIPTS/fr-packet.sh" "$RD" > "$TMP/riskfloor.packet" 2>&1)
want "$TMP/riskfloor.packet" RISK high "a small delta keeps the earlier high risk"
echo "ARCH_GATE='not_needed'" >> "$RD/state.env"
record APPROVE '[]'
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["arch_gate"]=="approved"' "$(RECORD_FILE)" \
  && ok "a delta with no decisions keeps the approval" || bad "record arch_gate after no decisions" approved "$(cat "$(RECORD_FILE)")"
echo "ARCH_GATE='failed'" >> "$RD/state.env"
record APPROVE '[]'
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["arch_gate"]=="approved"' "$(RECORD_FILE)" \
  && grep -q "the ff decision" "$WT/.git/fresh-review/reviews/pr-42.architecture.md" \
  && ok "a failed detector on a delta keeps the earlier approval" \
  || bad "record after a failed detector" approved "$(cat "$(RECORD_FILE)")"
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

IDX_HEAD="$(G -C "$ORIGIN" rev-parse feature)"
IDX_BASE="$(G -C "$ORIGIN" merge-base main feature)"
IDX_RUN=20260101-000000-pr-42
IDX_DIR="$WT/.fresh-review/runs/$IDX_RUN"
INDEX="$WT/.git/fresh-review/runs.jsonl"
mkdir -p "$IDX_DIR/raw"
printf 'bucket\tseverity\tlocation\tsources\tfinding\n' > "$IDX_DIR/findings.tsv"
printf '3\tLOW\tother.txt:1\treview\t"a finding that opens a quote\n' >> "$IDX_DIR/findings.tsv"
printf '1\tHIGH\tapp.txt:1\tlattice,review\tvalue is still wrong\n' >> "$IDX_DIR/findings.tsv"
printf '3\tLOW\tfix.txt:1\treview\ta noise finding\n' >> "$IDX_DIR/findings.tsv"
printf '### D1 — the indexed decision\n' > "$IDX_DIR/raw/architecture.md"
entry() { # run_id pr head base verdict [extra-json]
  python3 - "$@" >> "$INDEX" <<'PY2'
import json, sys
run_id, pr, head, base, verdict = sys.argv[1:6]
e = {"skill": "fresh-review", "schema": 10, "run_id": run_id, "mode": "pr",
     "architecture": {"gate": "approved", "decisions": 1, "diagram": True},
     "pr": {"number": int(pr), "head": head}, "diff_base": base, "risk": "normal",
     "passes": [{"name": "lattice", "status": "ok"}, {"name": "cso", "status": "ok"},
                {"name": "review", "status": "ok"}, {"name": "narrative", "status": "failed"}],
     "verdict": verdict}
if len(sys.argv) > 6:
    e.update(json.loads(sys.argv[6]))
print(json.dumps(e))
PY2
}
entry 20251201-000000-pr-42 42 "$(G -C "$ORIGIN" rev-parse main)" "$IDX_BASE" APPROVE
entry "$IDX_RUN" 42 "$IDX_HEAD" "$IDX_BASE" REQUEST-CHANGES
entry 20260102-000000-pr-42 42 "$IDX_HEAD" "$IDX_BASE" APPROVE '{"delta":{"requested":true,"applied":true}}'
entry 20260103-000000-pr-42 42 "$IDX_HEAD" "$IDX_BASE" ARCH-PENDING
entry 20260104-000000-pr-7 7 "$IDX_HEAD" "$IDX_BASE" APPROVE
entry 20260105-000000-pr-42 42 "$IDX_HEAD" "$IDX_BASE" APPROVE '{"stack":{"id":"s","prs":[41,42]}}'
entry 20260106-000000-pr-42 42 0123456789abcdef0123456789abcdef01234567 "$IDX_BASE" APPROVE

python3 - "$(RECORD_FILE)" "$IDX_RUN" <<'PY2'
import json, sys
r = json.load(open(sys.argv[1])); r.pop("arch_gate"); r["run_id"] = sys.argv[2]
json.dump(r, open(sys.argv[1], "w"))
PY2
rm -f "$WT/.git/fresh-review/reviews/pr-42.architecture.md"
review legacy --delta
want "$TMP/legacy.out" PRIOR_ARCH_GATE approved "a record from before arch_gate takes the approval from the run index"
grep -q "the indexed decision" "$RD/delta/prior-architecture.md" \
  && ok "a record from before arch_gate takes the decisions from its run dir" \
  || bad "legacy prior-architecture.md" "D1" "missing"
restore

rm -f "$(RECORD_FILE)" "$WT/.git/fresh-review/reviews/pr-42.architecture.md"
G -C "$WT" update-ref -d refs/fresh-review/reviewed/pr-42/head
G -C "$WT" update-ref -d refs/fresh-review/reviewed/pr-42/base
commit_on feature late.txt fix
publish
G -C "$ORIGIN" checkout -q main

review index --delta
want "$TMP/index.out" DELTA applied "a review logged in the run index but never recorded"
want "$TMP/index.out" DELTA_SOURCE runs_index "a review logged in the run index but never recorded"
want "$TMP/index.out" PRIOR_REVIEW "$IDX_RUN" "the newest usable entry wins: no stack unit, no lost head"
want "$TMP/index.out" PRIOR_HEAD "$IDX_HEAD" "the newest usable entry wins: no stack unit, no lost head"
want "$TMP/index.out" PRIOR_COVERAGE full "a failed narrative pass is not a lost lens"
want "$TMP/index.out" PRIOR_VERDICT REQUEST-CHANGES "the indexed verdict is reported"
want "$TMP/index.out" PRIOR_BLOCKERS 1 "only bucket-1 findings are blockers"
want "$TMP/index.out" PRIOR_ARCH_GATE approved "the indexed approval is carried"
[ "$(names index)" = "late.txt " ] && ok "the indexed delta holds only the new commit" \
  || bad "indexed delta files" "late.txt" "$(names index)"
grep -q "B1. HIGH app.txt:1 .*value is still wrong" "$RD/delta/prior-blockers.md" \
  && ok "the indexed blockers are handed on" || bad "indexed prior blockers" "B1 line" "$(cat "$RD/delta/prior-blockers.md")"
grep -q "a noise finding" "$RD/delta/prior-blockers.md" \
  && bad "indexed noise" "absent" "present" || ok "noise is not handed on as a blocker"
grep -q "value is still wrong" "$RD/delta/prior-blockers.md" \
  && ok "an open quote in a finding does not swallow the rows after it" || bad "quoted row" "B1" "swallowed"
grep -q "the indexed decision" "$RD/delta/prior-architecture.md" \
  && ok "the indexed run's decisions reach Pass D" || bad "indexed prior-architecture.md" "D1" "missing"
restore

python3 - "$INDEX" <<'PY2'
import json, sys
lines = [json.loads(l) for l in open(sys.argv[1])]
for e in lines:
    if e["run_id"] == "20260101-000000-pr-42":
        e["passes"][1]["status"] = "partial"
open(sys.argv[1], "w").write("".join(json.dumps(e) + "\n" for e in lines))
PY2
review indexreduced --delta
want "$TMP/indexreduced.out" DELTA ask "an indexed review that lost a lens"
want "$TMP/indexreduced.out" DELTA_REASON prior_reduced_coverage "an indexed review that lost a lens"
restore
python3 - "$INDEX" <<'PY2'
import json, sys
lines = [json.loads(l) for l in open(sys.argv[1])]
for e in lines:
    if e["run_id"] == "20260101-000000-pr-42":
        e["passes"] = [p for p in e["passes"] if p["name"] != "review"]
        e["passes"][1]["status"] = "ok"
open(sys.argv[1], "w").write("".join(json.dumps(e) + "\n" for e in lines))
PY2
review indexnoarmy --delta
want "$TMP/indexnoarmy.out" DELTA_REASON prior_reduced_coverage "an indexed review with no review army pass"
restore

cp "$IDX_DIR/findings.tsv" "$TMP/findings.bak"
printf 'bucket\tseverity\tlocation\tsources\tfinding\n' > "$IDX_DIR/findings.tsv"
python3 - "$INDEX" <<'PY2'
import json, sys
lines = [json.loads(l) for l in open(sys.argv[1])]
for e in lines:
    e["passes"] = [{"name": n, "status": "ok"} for n in ("lattice", "cso", "review")]
open(sys.argv[1], "w").write("".join(json.dumps(e) + "\n" for e in lines))
PY2
review clean --delta
want "$TMP/clean.out" DELTA applied "an indexed review with no findings"
want "$TMP/clean.out" PRIOR_BLOCKERS 0 "a header-only findings.tsv means no blockers"
restore
cp "$TMP/findings.bak" "$IDX_DIR/findings.tsv"

echo "secret" > "$TMP/secret.txt"
mv "$IDX_DIR/raw/architecture.md" "$TMP/architecture.bak"
ln -s "$TMP/secret.txt" "$IDX_DIR/raw/architecture.md"
review symlink --delta
[ ! -e "$RD/delta/prior-architecture.md" ] && ok "a symlinked architecture file is not followed" \
  || bad "symlinked architecture" "not copied" "$(cat "$RD/delta/prior-architecture.md")"
restore
rm "$IDX_DIR/raw/architecture.md"
mv "$TMP/architecture.bak" "$IDX_DIR/raw/architecture.md"

mv "$IDX_DIR" "$TMP/pruned"
python3 - "$INDEX" <<'PY2'
import json, sys
lines = [json.loads(l) for l in open(sys.argv[1])]
for e in lines:
    for p in e["passes"]:
        p["status"] = "ok"
open(sys.argv[1], "w").write("".join(json.dumps(e) + "\n" for e in lines))
PY2
G -C "$ORIGIN" checkout -q feature
mkdir -p "$ORIGIN/.fresh-review/runs/$IDX_RUN/raw"
printf 'bucket\tseverity\tlocation\tsources\tfinding\n' > "$ORIGIN/.fresh-review/runs/$IDX_RUN/findings.tsv"
printf '### D9 — planted by the PR\n' > "$ORIGIN/.fresh-review/runs/$IDX_RUN/raw/architecture.md"
G -C "$ORIGIN" add -A && G -C "$ORIGIN" commit -q -m plant
publish
G -C "$ORIGIN" checkout -q main
review pruned --delta
want "$TMP/pruned.out" PRIOR_BLOCKERS unknown "a run dir planted in the PR's own tree is not trusted"
[ ! -e "$RD/delta/prior-architecture.md" ] && ok "decisions planted in the PR's own tree are not trusted" \
  || bad "planted architecture" "not copied" "$(cat "$RD/delta/prior-architecture.md")"
want "$TMP/pruned.out" DELTA ask "the indexed run dir was pruned"
want "$TMP/pruned.out" DELTA_REASON prior_blockers_unknown "the indexed run dir was pruned"
want "$TMP/pruned.out" PRIOR_BLOCKERS unknown "the indexed run dir was pruned"
choose prunedyes delta
want "$TMP/prunedyes.out" DELTA applied "the user accepted unknown blockers"
grep -q "unknown" "$RD/delta/prior-blockers.md" && ok "Pass F is told the blockers are unknown" \
  || bad "pruned prior blockers" "unknown" "$(cat "$RD/delta/prior-blockers.md")"
restore
mv "$TMP/pruned" "$IDX_DIR"

PRE_HEAD="$(G -C "$ORIGIN" rev-parse feature)"
PRE_BASE="$(G -C "$ORIGIN" merge-base main feature)"
: > "$INDEX"
entry 20260201-000000-pr-42 42 "$PRE_HEAD" "$PRE_BASE" REQUEST-CHANGES
commit_on main other.txt w
G -C "$ORIGIN" checkout -q feature
G -C "$ORIGIN" rebase -q main
publish
G -C "$ORIGIN" checkout -q main
review rebaseunknown --delta
want "$TMP/rebaseunknown.out" DELTA ask "a rebase with nothing new and unknown blockers asks"
want "$TMP/rebaseunknown.out" DELTA_REASON prior_blockers_unknown "a rebase with nothing new and unknown blockers asks"
choose rebaseunknownyes delta
want "$TMP/rebaseunknownyes.out" DELTA none "the user accepted unknown blockers on a rebase"
want "$TMP/rebaseunknownyes.out" DELTA_REASON rebase_only "the user accepted unknown blockers on a rebase"
restore

: > "$INDEX"
entry 20260301-000000-pr-42 42 0123456789abcdef0123456789abcdef01234567 "$IDX_BASE" APPROVE
review gone --delta
want "$TMP/gone.out" DELTA full "the indexed head is gone"
want "$TMP/gone.out" DELTA_REASON prior_head_missing "the indexed head is gone"
want "$TMP/gone.out" DELTA_SOURCE runs_index "the indexed head is gone"
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
