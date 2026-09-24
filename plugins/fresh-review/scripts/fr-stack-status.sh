#!/usr/bin/env bash
# fr-stack-status.sh <RUN_DIR> [<unit> <verdict> [<blockers>]] — Step S progress.
#
# Output contract (stdout):
#   === FRESH-REVIEW STACK STATUS ===
#   STATUS: ok | error
#   REASON: <slug>                   (only when error)
#   UNIT_<k>: prs=<n,n> state=<pending|verdict> blockers=<n|->
#   REPORTED: <n>/<units>
#   STACK_VERDICT: pending | INCOMPLETE | APPROVE | APPROVE-WITH-COMMENTS | REQUEST-CHANGES
#   === END ===

set -u

RUN_DIR="${1:?usage: fr-stack-status.sh <RUN_DIR> [<unit> <verdict> [<blockers>]]}"

python3 - "$RUN_DIR/stack/status.tsv" "${2:-}" "${3:-}" "${4:--}" <<'PY'
import os, sys

path, unit, verdict, blockers = sys.argv[1:5]
verdicts = ["APPROVE", "APPROVE-WITH-COMMENTS", "REQUEST-CHANGES", "ARCH-PENDING", "SKIPPED"]


def block(lines):
    print("\n".join(["=== FRESH-REVIEW STACK STATUS ==="] + lines + ["=== END ==="]))


def error(reason):
    block(["STATUS: error", f"REASON: {reason}"])
    sys.exit(0)


if not os.path.isfile(path):
    error("no_stack_status")
with open(path) as fh:
    rows = [line.rstrip("\n").split("\t") for line in fh if line.strip()]

if unit:
    verdict = verdict.upper().replace(" ", "-")
    if verdict not in verdicts:
        error("bad_verdict")
    if blockers != "-" and not blockers.isdigit():
        error("bad_blockers")
    match = [row for row in rows if row[0] == unit]
    if not match:
        error("no_such_unit")
    match[0][2], match[0][3] = verdict, blockers
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        fh.write("".join("\t".join(row) + "\n" for row in rows))
    os.replace(tmp, path)

states = [row[2] for row in rows]
reported = sum(state != "pending" for state in states)
if "REQUEST-CHANGES" in states:
    stack_verdict = "REQUEST-CHANGES"
elif reported < len(rows) or "ARCH-PENDING" in states:
    stack_verdict = "pending"
elif "SKIPPED" in states:
    stack_verdict = "INCOMPLETE"
elif "APPROVE-WITH-COMMENTS" in states:
    stack_verdict = "APPROVE-WITH-COMMENTS"
else:
    stack_verdict = "APPROVE"

lines = ["STATUS: ok"]
lines += [f"UNIT_{k}: prs={prs} state={state} blockers={b}" for k, prs, state, b in rows]
lines += [f"REPORTED: {reported}/{len(rows)}", f"STACK_VERDICT: {stack_verdict}"]
block(lines)
PY
