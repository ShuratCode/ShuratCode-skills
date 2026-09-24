#!/usr/bin/env bash
# fr-stack.sh <RUN_DIR> — Step S. Stack mode only.
#
# Output contract (stdout):
#   === FRESH-REVIEW STACK ===
#   STACK: resolved | unresolved
#   REASON: <slug>                   (only when unresolved)
#   STACK_ID / PRS / FORK_AT
#   NEXT: review_here | handoff
#   REVIEW_ARGS: --pr <n> [--codex]          (only when NEXT: review_here)
#   UNITS / UNIT_<k> / PLAN / HANDOFF_DIR    (only when NEXT: handoff)
#   UNIT_<k>: prs=<n,n> lines=<n> files=<n> risk=<normal|high>
#   === END ===

set -u

RUN_DIR="${1:?usage: fr-stack.sh <RUN_DIR>}"
STATE="$RUN_DIR/state.env"
set -a
# shellcheck disable=SC1090
. "$STATE"
set +a

if ! command -v gh >/dev/null 2>&1; then
  printf '%s\n' "=== FRESH-REVIEW STACK ===" "STACK: unresolved" "REASON: gh_missing" "=== END ==="
  exit 0
fi

export FR_RUN_DIR="$RUN_DIR"
export FR_PACKET="$CLAUDE_PLUGIN_ROOT/scripts/fr-packet.sh"
export FR_HANDOFF_CMD="${FR_HANDOFF_CMD:-/fresh-review:review}"
export FR_STACK_SMALL_LINES="${FR_STACK_SMALL_LINES:-80}"

python3 - <<'PY'
import json, os, re, subprocess, sys, time

env = os.environ
run_dir = env["FR_RUN_DIR"]
state_path = os.path.join(run_dir, "state.env")
stack_dir = os.path.join(run_dir, "stack")
handoff_dir = os.path.join(run_dir, "handoff")
os.makedirs(stack_dir, exist_ok=True)
os.makedirs(handoff_dir, exist_ok=True)
run_id = env["RUN_ID"]
small_lines = int(env["FR_STACK_SMALL_LINES"])
fields = "number,title,url,state,headRefName,baseRefName,headRefOid,isCrossRepository"
temp_refs = []


def quoted(key, value):
    escaped = str(value).replace("'", "'\\''")
    return f"{key}='{escaped}'\n"


def kv(key, value):
    with open(state_path, "a") as fh:
        fh.write(quoted(key, value))


def block(lines):
    print("\n".join(["=== FRESH-REVIEW STACK ==="] + lines + ["=== END ==="]))


def unresolved(reason):
    cleanup()
    kv("STACK_RESOLVED", "0")
    block(["STACK: unresolved", f"REASON: {reason}"])
    sys.exit(0)


def run(*args, check=True):
    proc = subprocess.run(args, capture_output=True, text=True)
    if check and proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip())
    return proc.stdout.strip()


def cleanup():
    for ref in temp_refs:
        subprocess.run(["git", "update-ref", "-d", ref], capture_output=True)


def gh_json(*args):
    try:
        return json.loads(run("gh", *args))
    except Exception:
        return None


def parse_refs(raw):
    refs = [r for r in re.split(r"[,\s]+", raw) if r]
    if not refs:
        unresolved("no_stack_ref")
    repo_url = None
    numbers = []
    for ref in refs:
        if re.fullmatch(r"#?\d+", ref):
            numbers.append(int(ref.lstrip("#")))
            continue
        match = re.search(r"github\.com/.+/pull/(\d+)", ref)
        if not match:
            unresolved("bad_stack_ref")
        if repo_url is None:
            repo_url = (run("gh", "repo", "view", "--json", "url", "-q", ".url", check=False) or "").rstrip("/")
        if not repo_url or not ref.split("://")[-1].startswith(repo_url.split("://")[-1] + "/pull/"):
            unresolved("foreign_repo")
        numbers.append(int(match.group(1)))
    return list(dict.fromkeys(numbers))


def load_prs(numbers):
    listed = gh_json("pr", "list", "--state", "open", "--limit", "300", "--json", fields)
    if listed is None:
        unresolved("gh_pr_list_failed")
    by_number = {pr["number"]: pr for pr in listed}
    for number in numbers:
        if number not in by_number:
            pr = gh_json("pr", "view", str(number), "--json", fields)
            if not pr or not pr.get("number"):
                unresolved("gh_pr_view_failed")
            by_number[number] = pr
    by_head = {pr["headRefName"]: pr for pr in listed if not pr.get("isCrossRepository")}
    children = {}
    for pr in listed:
        children.setdefault(pr["baseRefName"], []).append(pr)
    return by_number, by_head, children


def discover_chain(start, by_head, children):
    chain = [start]
    while chain[0]["baseRefName"] in by_head and len(chain) < 30:
        parent = by_head[chain[0]["baseRefName"]]
        if parent in chain:
            break
        chain.insert(0, parent)
    fork_at = None
    while len(chain) < 30:
        above = children.get(chain[-1]["headRefName"], [])
        if not above:
            break
        if len(above) > 1:
            fork_at = chain[-1]["number"]
            break
        chain.append(above[0])
    return chain, fork_at


def order_given(prs):
    heads = {pr["headRefName"]: pr for pr in prs}
    roots = [pr for pr in prs if pr["baseRefName"] not in heads]
    if len(roots) != 1:
        return prs
    chain = [roots[0]]
    while True:
        above = [pr for pr in prs if pr["baseRefName"] == chain[-1]["headRefName"] and pr not in chain]
        if len(above) != 1:
            break
        chain.append(above[0])
    return chain if len(chain) == len(prs) else prs


def fetch(chain):
    specs = []
    for index, pr in enumerate(chain):
        ref = f"refs/fresh-review/stack-{run_id}-{pr['number']}"
        temp_refs.append(ref)
        specs.append(f"+pull/{pr['number']}/head:{ref}")
        pr["_ref"] = ref
        if not linked(chain, index):
            base = pr["baseRefName"]
            specs.append(f"+refs/heads/{base}:refs/remotes/origin/{base}")
    try:
        run("git", "fetch", "--quiet", "origin", *dict.fromkeys(specs))
    except Exception:
        unresolved("pr_fetch_failed")
    for pr in chain:
        pr["_head"] = run("git", "rev-parse", pr["_ref"])


def linked(chain, index):
    return index > 0 and chain[index]["baseRefName"] == chain[index - 1]["headRefName"]


def packet(name, base, head):
    directory = os.path.join(stack_dir, name)
    os.makedirs(os.path.join(directory, "packet"), exist_ok=True)
    with open(os.path.join(directory, "state.env"), "w") as fh:
        for key, value in [
            ("REVIEW_SCOPE", "pr"), ("CHECKPOINT", "pr_remote"), ("CHECKPOINT_SHA", head),
            ("DIFF_CMD", f"git diff {base} {head}"), ("BASE", env.get("BASE", "")),
            ("DIFF_BASE", base), ("SOURCE_ROOT", env["REPO_ROOT"]),
            ("CODEX_REQUESTED", "0"), ("CODEX_REASON", "none"),
        ]:
            fh.write(quoted(key, value))
    out = run("bash", env["FR_PACKET"], directory)
    keys = dict(line.split(": ", 1) for line in out.splitlines() if ": " in line)
    files = set()
    with open(os.path.join(directory, "packet", "files.txt")) as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) > 1:
                files.add(parts[-1])
    return {"lines": int(keys.get("LINES", 0)), "risk": keys.get("RISK", "normal"), "files": files}


def join_decision(unit, pr, prev, pr_stats, index, chain):
    if not linked(chain, index):
        return None, f"#{pr['number']} is not based on #{prev['number']}"
    if pr_stats["risk"] == "high":
        return None, f"#{pr['number']} is high risk"
    if unit["risk"] == "high":
        return None, f"#{prev['number']} is high risk and stays alone"
    combined = packet(f"join-{unit['prs'][0]}-{pr['number']}", unit["base"], pr["_head"])
    if combined["risk"] == "high":
        return None, f"#{pr['number']} would make the combined review high risk"
    if pr_stats["lines"] <= small_lines:
        return combined, f"#{pr['number']} is small ({pr_stats['lines']} lines)"
    if unit["lines"] <= small_lines:
        return combined, f"the unit before #{pr['number']} is small ({unit['lines']} lines)"
    shared = unit["files"] & pr_stats["files"]
    smaller = min(len(unit["files"]), len(pr_stats["files"])) or 1
    if len(shared) / smaller >= 0.5:
        return combined, f"#{pr['number']} changes {len(shared)} of the same files"
    return None, f"#{pr['number']} changes different files and is not small"


def plan_units(chain):
    units = []
    for index, pr in enumerate(chain):
        base = run("git", "merge-base",
                   chain[index - 1]["_head"] if linked(chain, index) else f"origin/{pr['baseRefName']}",
                   pr["_head"], check=False)
        if not base:
            unresolved("no_merge_base")
        pr["_base"] = base
        stats = packet(f"pr-{pr['number']}", base, pr["_head"])
        pr["_stats"] = stats
        if units:
            combined, reason = join_decision(units[-1], pr, chain[index - 1], stats, index, chain)
            if combined:
                unit = units[-1]
                unit["prs"].append(pr["number"])
                unit["head"] = pr["_head"]
                unit["lines"] = combined["lines"]
                unit["files"] = combined["files"]
                unit["risk"] = combined["risk"]
                unit["why"].append(reason)
                continue
            start = reason
        else:
            start = f"#{pr['number']} is the bottom of the stack"
        units.append({"prs": [pr["number"]], "base": base, "head": pr["_head"],
                      "lines": stats["lines"], "files": set(stats["files"]),
                      "risk": stats["risk"], "why": [start]})
    return units


def pr_list(numbers):
    return ", ".join(f"#{n}" for n in numbers)


def handoff_text(unit, k, units):
    top, bottom = unit["prs"][-1], unit["prs"][0]
    args = f"--pr {top}" if len(unit["prs"]) == 1 else f"--pr {top} --since-pr {bottom}"
    if env.get("CODEX_REQUESTED") == "1":
        args += " --codex"
    if len(unit["prs"]) == 1:
        scope = f"- Review PR #{top} on its own: from its base branch to its head."
    else:
        scope = (f"- Review PRs {pr_list(unit['prs'])} as one change: "
                 f"from the base of #{bottom} to the head of #{top}.")
    others = [f"unit {j} ({pr_list(u['prs'])})" for j, u in enumerate(units, 1) if j != k]
    lines = [
        f"{env['FR_HANDOFF_CMD']} {args}",
        "",
        f"Stack review handoff: unit {k} of {len(units)}, stack {run_id}.",
        "",
        "Scope",
        scope,
        f"- Why: {'; '.join(unit['why'])}.",
    ]
    if others:
        lines.append(f"- Other units run in their own sessions: {', '.join(others)}. "
                     "Do not review their changes here.")
    lines += [
        "",
        "Rules for this session",
        "- The flags on the first line are final. Run the full fresh-review flow with them. "
        "This is not a stack request.",
        "- The architecture gate applies to this unit on its own.",
        "- Keep this handoff out of every reviewer subagent. Reviewers get the packet only.",
        "- A later PR in the stack may change this code. A finding still counts here: "
        "it belongs to the PR that adds the code.",
        f"- In run.json, add \"stack\": {{\"id\": \"{run_id}\", \"unit\": {k}, \"units\": {len(units)}}}.",
        "- End the chat output with this line, filled in, so the user can paste it to the orchestrator:",
        f"  STACK REPORT — {run_id} · unit {k}/{len(units)} · PRs {pr_list(unit['prs'])} · <VERDICT> · blockers <n>",
    ]
    return "\n".join(lines) + "\n"


def write_plan(chain, units, fork_at):
    titles = {pr["number"]: pr.get("title", "") for pr in chain}
    rows = [
        f"# Stack review plan — {run_id}",
        "",
        "PRs, bottom to top: " + " → ".join(f"#{pr['number']}" for pr in chain),
        "",
        "| Unit | PRs | Lines | Files | Risk | Why |",
        "|---|---|---|---|---|---|",
    ]
    for k, unit in enumerate(units, 1):
        names = "<br>".join(f"#{n} {titles[n]}" for n in unit["prs"])
        rows.append(f"| {k} | {names} | {unit['lines']} | {len(unit['files'])} | "
                    f"{unit['risk']} | {'; '.join(unit['why'])} |")
    if fork_at:
        rows += ["", f"The stack branches above #{fork_at}. Only the path to the given PR is planned."]
    path = os.path.join(stack_dir, "plan.md")
    with open(path, "w") as fh:
        fh.write("\n".join(rows) + "\n")
    return path


def write_run_json(chain, units, fork_at):
    now = int(time.time())
    record = {
        "skill": "fresh-review", "schema": 10, "run_id": run_id,
        "ts_start": env.get("TS_START", ""), "ts_end": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "duration_s": now - int(env.get("T0", now)),
        "repo": os.path.basename(env["REPO_ROOT"]), "branch": env.get("BRANCH", ""),
        "base": env.get("BASE", ""), "mode": "stack",
        "stack": {
            "id": run_id, "prs": [pr["number"] for pr in chain], "fork_at": fork_at,
            "units": [{"unit": k, "prs": u["prs"], "lines": u["lines"], "files": len(u["files"]),
                       "risk": u["risk"], "why": u["why"]} for k, u in enumerate(units, 1)],
        },
        "passes": [], "verdict": "HANDOFF",
        "tools": {"gstack": int(env.get("HAS_GSTACK", 0)), "codex": int(env.get("HAS_CODEX", 0)),
                  "gh": int(env.get("HAS_GH", 0))},
    }
    with open(os.path.join(run_dir, "run.json"), "w") as fh:
        json.dump(record, fh)


def review_here(pr):
    args = f"--pr {pr['number']}" + (" --codex" if env.get("CODEX_REQUESTED") == "1" else "")
    kv("STACK_RESOLVED", "1")
    kv("STACK_PRS", pr["number"])
    kv("STACK_NEXT", "review_here")
    block(["STACK: resolved", f"STACK_ID: {run_id}", f"PRS: {pr['number']}", "FORK_AT: none",
           "NEXT: review_here", f"REVIEW_ARGS: {args}"])


def main():
    numbers = parse_refs(env.get("STACK_REFS", ""))
    by_number, by_head, children = load_prs(numbers)
    if len(numbers) == 1:
        chain, fork_at = discover_chain(by_number[numbers[0]], by_head, children)
    else:
        chain, fork_at = order_given([by_number[n] for n in numbers]), None
    if len(chain) == 1:
        review_here(chain[0])
        return
    fetch(chain)
    units = plan_units(chain)
    plan = write_plan(chain, units, fork_at)
    with open(os.path.join(stack_dir, "status.tsv"), "w") as fh:
        for k, unit in enumerate(units, 1):
            fh.write(f"{k}\t{','.join(map(str, unit['prs']))}\tpending\t-\n")
    for k, unit in enumerate(units, 1):
        with open(os.path.join(handoff_dir, f"unit-{k}.md"), "w") as fh:
            fh.write(handoff_text(unit, k, units))
    write_run_json(chain, units, fork_at)
    cleanup()

    prs = " ".join(str(pr["number"]) for pr in chain)
    kv("STACK_RESOLVED", "1")
    kv("STACK_ID", run_id)
    kv("STACK_PRS", prs)
    kv("STACK_UNITS", len(units))
    kv("STACK_PLAN", plan)
    kv("STACK_HANDOFF_DIR", handoff_dir)
    kv("STACK_NEXT", "handoff")
    lines = ["STACK: resolved", f"STACK_ID: {run_id}", f"PRS: {prs}",
             f"FORK_AT: {fork_at or 'none'}", "NEXT: handoff", f"UNITS: {len(units)}"]
    for k, unit in enumerate(units, 1):
        lines.append(f"UNIT_{k}: prs={','.join(map(str, unit['prs']))} lines={unit['lines']} "
                     f"files={len(unit['files'])} risk={unit['risk']}")
    lines += [f"PLAN: {plan}", f"HANDOFF_DIR: {handoff_dir}"]
    block(lines)


try:
    main()
except SystemExit:
    raise
except Exception as exc:
    cleanup()
    kv("STACK_RESOLVED", "0")
    block(["STACK: unresolved", "REASON: stack_script_failed"])
    print(str(exc), file=sys.stderr)
PY
