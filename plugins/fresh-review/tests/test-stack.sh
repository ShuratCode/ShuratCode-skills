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
case "$1 $2" in
  "pr list") cat "$GH_PR_LIST" ;;
  "pr view")
    python3 - "$GH_PR_LIST" "$3" <<'PY'
import json, sys
prs = json.load(open(sys.argv[1]))
ref = sys.argv[2]
for pr in prs:
    if str(pr["number"]) == ref or pr["headRefName"] == ref:
        print(json.dumps(pr)); sys.exit(0)
sys.exit(1)
PY
    ;;
  "repo view") echo "https://github.com/acme/widgets" ;;
  *) echo "stub gh: unexpected: $*" >&2; exit 9 ;;
esac
EOF
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"

ORIGIN="$TMP/origin"
mkdir -p "$ORIGIN"
G -C "$ORIGIN" init -q -b main
echo base > "$ORIGIN/readme.txt"
G -C "$ORIGIN" add -A && G -C "$ORIGIN" commit -q -m base
MAIN_SHA="$(G -C "$ORIGIN" rev-parse HEAD)"

lines() { seq 1 "$2" | sed "s/^/value_$1 = /"; }
branch() { # name parent pr-number setup...
  local name="$1" parent="$2" number="$3"; shift 3
  G -C "$ORIGIN" checkout -q -b "$name" "$parent"
  "$@"
  G -C "$ORIGIN" add -A && G -C "$ORIGIN" commit -q -m "$name"
  G -C "$ORIGIN" update-ref "refs/pull/$number/head" "$(G -C "$ORIGIN" rev-parse HEAD)"
}
f1() { mkdir -p "$ORIGIN/lib"; lines a 120 > "$ORIGIN/lib/a.py"; }
f2() { lines b 5 >> "$ORIGIN/lib/a.py"; }
f3() { echo "check = 1" > "$ORIGIN/auth.py"; }
f4() { mkdir -p "$ORIGIN/docs"; lines d 100 > "$ORIGIN/docs/d.txt"; }
f5() { mkdir -p "$ORIGIN/other"; lines e 100 > "$ORIGIN/other/e.txt"; }
branch f1 main 41 f1
branch f2 f1 42 f2
branch f3 f2 43 f3
branch f4 f3 44 f4
branch f5 f4 45 f5
G -C "$ORIGIN" checkout -q main

pr_list() { # out  number:head:base...
  python3 - "$@" <<'PY'
import json, sys
out = sys.argv[1]
prs = []
for spec in sys.argv[2:]:
    n, head, base = spec.split(":")
    prs.append({"number": int(n), "title": f"SECRET TITLE {n}", "url": f"https://github.com/acme/widgets/pull/{n}",
                "state": "OPEN", "headRefName": head, "baseRefName": base, "headRefOid": "",
                "isCrossRepository": False})
json.dump(prs, open(out, "w"))
PY
}
pr_list "$TMP/stack.json" 41:f1:main 42:f2:f1 43:f3:f2 44:f4:f3 45:f5:f4 46:other:main
pr_list "$TMP/forked.json" 41:f1:main 42:f2:f1 43:f3:f2 44:f4:f3 45:f5:f4 47:x:f2
export GH_PR_LIST="$TMP/stack.json"

WT="$TMP/wt"
git clone -q "$ORIGIN" "$WT"
G -C "$WT" remote set-url origin "git@github.com:acme/widgets.git"
G -C "$WT" config --local "url.$ORIGIN.insteadOf" "git@github.com:acme/widgets.git"
echo ".fresh-review/" > "$WT/.gitignore"
G -C "$WT" add .gitignore && G -C "$WT" commit -q -m ignore

stack() { # label refs
  (cd "$WT" && bash "$SCRIPTS/fr-preflight.sh" --stack "$2" > "$TMP/$1.pf" 2>&1)
  local rd; rd="$(key "$TMP/$1.pf" RUN_DIR)"
  echo "$rd" > "$TMP/$1.rd"
  (cd "$WT" && bash "$SCRIPTS/fr-stack.sh" "$rd" > "$TMP/$1.out" 2>"$TMP/$1.err")
}

printf '\n\033[1mfresh-review stack orchestrator\033[0m\n'

stack disc 43
want "$TMP/disc.pf" MODE stack "preflight --stack"
want "$TMP/disc.out" STACK resolved "one ref discovers the stack"
want "$TMP/disc.out" PRS "41 42 43 44 45" "one ref discovers the stack"
want "$TMP/disc.out" FORK_AT none "a linear stack"
want "$TMP/disc.out" UNITS 4 "grouping"
want "$TMP/disc.out" UNIT_1 "prs=41,42 lines=127 files=1 risk=normal" "a small PR joins its parent"
want "$TMP/disc.out" UNIT_2 "prs=43 lines=3 files=1 risk=high" "a high-risk PR stays alone"
want "$TMP/disc.out" UNIT_3 "prs=44 lines=102 files=1 risk=normal" "a PR above a high-risk unit starts a new unit"
want "$TMP/disc.out" UNIT_4 "prs=45 lines=102 files=1 risk=normal" "an unrelated, not-small PR stays alone"

RD="$(cat "$TMP/disc.rd")"
H1="$RD/handoff/unit-1.md"
[ "$(head -1 "$H1")" = "/fresh-review:review --pr 42 --since-pr 41" ] \
  && ok "a combined unit hands off --pr <top> --since-pr <bottom>" \
  || bad "unit 1 invocation" "--pr 42 --since-pr 41" "$(head -1 "$H1")"
[ "$(head -1 "$RD/handoff/unit-2.md")" = "/fresh-review:review --pr 43" ] \
  && ok "a single-PR unit hands off --pr <n>" \
  || bad "unit 2 invocation" "--pr 43" "$(head -1 "$RD/handoff/unit-2.md")"
[ "$(head -1 "$RD/handoff/unit-1-rereview.md")" = "/fresh-review:review --pr 42 --since-pr 41 --delta" ] \
  && ok "a unit's re-review handoff adds --delta" \
  || bad "unit 1 re-review invocation" "--pr 42 --since-pr 41 --delta" "$(head -1 "$RD/handoff/unit-1-rereview.md")"
grep -q "SECRET TITLE" "$RD"/handoff/*.md \
  && bad "handoffs carry no PR titles" "no title" "title found" \
  || ok "handoffs carry no PR titles"
grep -q "#42 is small" "$H1" && ok "the handoff says why PRs were combined" \
  || bad "join reason" "#42 is small" "$(grep Why "$H1")"
grep -q "SECRET TITLE 41" "$RD/stack/plan.md" && ok "the plan shows titles to the human" \
  || bad "plan titles" "SECRET TITLE 41" "missing"
python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); assert r["mode"]=="stack" and len(r["stack"]["units"])==4' \
  "$RD/run.json" && ok "run.json records the stack plan" || bad "run.json" "mode stack, 4 units" "$(cat "$RD/run.json")"
[ -z "$(G -C "$WT" for-each-ref refs/fresh-review/)" ] && ok "temporary stack refs are deleted" \
  || bad "temp refs" "none" "$(G -C "$WT" for-each-ref refs/fresh-review/)"
[ -z "$(G -C "$WT" status --porcelain)" ] && ok "the user's checkout is untouched" \
  || bad "checkout" "clean" "$(G -C "$WT" status --porcelain)"

grep -q "STACK REPORT — .* · unit 1/4 · PRs #41, #42 · <VERDICT> · blockers <n>" "$H1" \
  && ok "the handoff asks for a stack report line" || bad "report line" "STACK REPORT template" "$(grep REPORT "$H1")"

status() { bash "$SCRIPTS/fr-stack-status.sh" "$RD" "$@" > "$TMP/status.out"; }
status
want "$TMP/status.out" REPORTED 0/4 "a fresh plan has every unit pending"
want "$TMP/status.out" STACK_VERDICT pending "a fresh plan has every unit pending"
status 1 approve 0
want "$TMP/status.out" UNIT_1 "prs=41,42 state=APPROVE blockers=0" "a unit report is recorded"
want "$TMP/status.out" STACK_VERDICT pending "units still pending"
status 2 request-changes 2
want "$TMP/status.out" STACK_VERDICT REQUEST-CHANGES "one unit with blockers blocks the stack at once"
status 2 approve-with-comments 0; status 3 approve 0; status 4 approve 0
want "$TMP/status.out" REPORTED 4/4 "a unit can be reported again after fixes"
want "$TMP/status.out" STACK_VERDICT APPROVE-WITH-COMMENTS "the stack takes its weakest unit"
status 4 skipped
want "$TMP/status.out" STACK_VERDICT INCOMPLETE "a skipped unit leaves the stack incomplete"
status 9 approve 0
want "$TMP/status.out" REASON no_such_unit "an unknown unit is refused"
status 1 lgtm 0
want "$TMP/status.out" REASON bad_verdict "an unknown verdict is refused"

stack single 46
want "$TMP/single.out" NEXT review_here "a stack of one PR is reviewed in this session"
want "$TMP/single.out" REVIEW_ARGS "--pr 46" "a stack of one PR is reviewed in this session"
[ -z "$(ls "$(cat "$TMP/single.rd")/handoff" 2>/dev/null)" ] && ok "a stack of one PR writes no handoff" \
  || bad "single-PR handoff" "none" "$(ls "$(cat "$TMP/single.rd")/handoff")"
want "$TMP/disc.out" NEXT handoff "a stack of several PRs hands off"

stack order "42,41"
want "$TMP/order.out" PRS "41 42" "given refs are put in stack order"
want "$TMP/order.out" UNITS 1 "given refs are put in stack order"

stack gap "41 43"
want "$TMP/gap.out" UNITS 2 "PRs that are not linked never combine"
want "$TMP/gap.out" UNIT_2 "prs=43 lines=3 files=1 risk=high" "a gap uses the PR's own base branch"

stack url "https://github.com/acme/widgets/pull/41"
want "$TMP/url.out" PRS "41 42 43 44 45" "a pull URL for this repo"
stack foreign "https://github.com/other/repo/pull/41"
want "$TMP/foreign.out" REASON foreign_repo "a pull URL for another repo"
stack junk "not-a-pr"
want "$TMP/junk.out" REASON bad_stack_ref "a ref that is not a PR"

GH_PR_LIST="$TMP/forked.json" stack fork 41
want "$TMP/fork.out" PRS "41 42" "a branching stack stops at the fork"
want "$TMP/fork.out" FORK_AT 42 "a branching stack stops at the fork"

(cd "$WT" && bash "$SCRIPTS/fr-preflight.sh" --stack 41 --pr 42 >/dev/null 2>&1)
[ $? -eq 2 ] && ok "--stack with --pr is rejected" || bad "--stack with --pr" "exit 2" "exit $?"
(cd "$WT" && bash "$SCRIPTS/fr-preflight.sh" --since-pr 41 >/dev/null 2>&1)
[ $? -eq 2 ] && ok "--since-pr without --pr is rejected" || bad "--since-pr alone" "exit 2" "exit $?"

resolve() { # label pr since
  (cd "$WT" && bash "$SCRIPTS/fr-preflight.sh" --pr "$2" --since-pr "$3" > "$TMP/$1.pf" 2>&1)
  local rd; rd="$(key "$TMP/$1.pf" RUN_DIR)"
  (cd "$WT" && bash "$SCRIPTS/fr-pr-resolve.sh" "$rd" > "$TMP/$1.out" 2>&1)
  (cd "$WT" && bash "$SCRIPTS/fr-restore.sh" "$rd" >/dev/null 2>&1)
}

resolve unit 42 41
want "$TMP/unit.out" PR resolved "--pr 42 --since-pr 41"
want "$TMP/unit.out" STACK_PRS "41 42" "--pr 42 --since-pr 41"
want "$TMP/unit.out" UNIT_BASE main "--pr 42 --since-pr 41"
want "$TMP/unit.out" REVIEW_KEY pr-42-since-41 "a unit has its own review key"
want "$TMP/unit.out" DIFF_BASE "$MAIN_SHA" "the unit diff starts at the bottom PR's base"

resolve miss 43 99
want "$TMP/miss.out" REASON since_pr_not_below "--since-pr names a PR that is not below"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
