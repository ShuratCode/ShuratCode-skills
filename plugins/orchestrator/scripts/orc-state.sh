#!/usr/bin/env bash

set -u

CMD="${1:?usage: orc-state.sh <init|set|nudge|table|path> <ticket> [...]}"
TICKET="${2:?usage: orc-state.sh $CMD <ticket> [...]}"
shift 2

if [ -n "${ORC_STATE_DIR:-}" ]; then
  DIR="$ORC_STATE_DIR"
else
  COMMON="$(git rev-parse --git-common-dir 2>/dev/null)" || { echo "STATUS: error"; echo "REASON: not_a_repo"; exit 0; }
  DIR="$(cd "$COMMON" && pwd)/orchestrator"
fi

python3 - "$DIR" "$CMD" "$TICKET" "$@" <<'PY'
import csv, os, re, sys

state_dir, cmd, ticket, *args = sys.argv[1:]

TRACKS = {
    "feature":  ["spec", "design", "build", "review", "qa", "harvest", "ship"],
    "new-lane": ["spec", "design", "build", "review", "qa", "harvest", "ship"],
    "bug":      ["build", "review", "qa", "harvest", "ship"],
    "refactor": ["build", "review", "qa", "harvest", "ship"],
    "fast":     ["build", "review", "ship"],
}
COLS = ["stage", "session", "name", "status", "contract", "needs", "attempts"]
STATUSES = ["not started", "running", "waiting", "blocked", "done", "skipped", "stopped"]
CONTRACTS = ["-", "met", "unmet (nudged)", "unmet (stopped)"]
KEYS = ["session", "name", "status", "contract", "needs"]


def fail(reason):
    print("STATUS: error")
    print(f"REASON: {reason}")
    sys.exit(0)


if not re.fullmatch(r"[A-Za-z0-9._-]+", ticket):
    fail("bad_ticket")

path = os.path.join(state_dir, f"{ticket}.tsv")


def load():
    if not os.path.isfile(path):
        fail("no_state")
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f, delimiter="\t"))


def save(rows):
    os.makedirs(state_dir, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=COLS, delimiter="\t", lineterminator="\n")
        w.writeheader()
        w.writerows(rows)
    os.replace(tmp, path)


def row_for(rows, stage):
    for r in rows:
        if r["stage"] == stage:
            return r
    fail("no_such_stage")


def cell(v):
    return v.replace("|", "\\|") if v else "—"


if cmd == "path":
    print(path)
    sys.exit(0)

if cmd == "init":
    if not args or args[0] not in TRACKS:
        fail("bad_track")
    if os.path.isfile(path) and "--force" not in args:
        fail("state_exists")
    save([{"stage": s, "session": "", "name": "", "status": "not started",
           "contract": "-", "needs": "", "attempts": "0"} for s in TRACKS[args[0]]])
    print("STATUS: ok")
    print(f"STATE: {path}")
    sys.exit(0)

if cmd == "set":
    if not args:
        fail("no_stage")
    rows = load()
    r = row_for(rows, args[0])
    for pair in args[1:]:
        if "=" not in pair:
            fail("bad_pair")
        k, v = pair.split("=", 1)
        if k not in KEYS or "\t" in v or "\n" in v:
            fail("bad_key")
        if k == "status" and v not in STATUSES:
            fail("bad_status")
        if k == "contract" and v not in CONTRACTS:
            fail("bad_contract")
        r[k] = v
    save(rows)
    print("STATUS: ok")
    sys.exit(0)

if cmd == "nudge":
    if not args:
        fail("no_stage")
    rows = load()
    r = row_for(rows, args[0])
    n = int(r["attempts"] or 0)
    if n == 0:
        r["attempts"] = "1"
        r["contract"] = "unmet (nudged)"
        save(rows)
        print("STATUS: ok")
        print("NUDGE: allowed")
    else:
        r["contract"] = "unmet (stopped)"
        r["status"] = "stopped"
        save(rows)
        print("STATUS: ok")
        print("NUDGE: refused")
    sys.exit(0)

if cmd == "table":
    rows = load()
    print("| Stage | Session | Status | Contract | Needs you |")
    print("|---|---|---|---|---|")
    for r in rows:
        if r["session"]:
            label = r["name"] or r["session"]
            session = f"[{cell(label)}](#{r['session']})"
        else:
            session = "—"
        contract = "—" if r["contract"] == "-" else r["contract"]
        print(f"| {r['stage'].upper()} | {session} | {r['status']} | {contract} | {cell(r['needs'])} |")
    sys.exit(0)

fail("bad_command")
PY
