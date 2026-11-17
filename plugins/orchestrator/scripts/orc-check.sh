#!/usr/bin/env bash

set -u

REPORT="${1:?usage: orc-check.sh <report-file> [repo-dir]}"
REPO="${2:-$PWD}"
HERE="$(cd "$(dirname "$0")" && pwd)"
CONTRACTS="${ORC_CONTRACTS:-$HERE/../skills/orchestrator/references/contracts.md}"

python3 - "$REPORT" "$REPO" "$CONTRACTS" <<'PY'
import os, re, subprocess, sys

report_path, repo, contracts_path = sys.argv[1:4]

STAGES = ["spec", "design", "build", "review", "qa", "harvest", "ship"]
VERDICTS = ["COMMIT-WITH-FIXES", "COMMIT", "DO-NOT-COMMIT",
            "APPROVE-WITH-COMMENTS", "APPROVE", "REQUEST-CHANGES"]
STACK_RE = re.compile(
    r"^STACK REPORT — \S+ · unit \d+/\d+ · PRs? .+ · "
    r"(APPROVE|APPROVE-WITH-COMMENTS|REQUEST-CHANGES|ARCH-PENDING) · blockers \d+$")
RESULT_RE = re.compile(r"^(.+?)\s+(?:—|--|-)\s+(pass|fail|not-run)\b")


def out(lines):
    print("\n".join(["=== ORCHESTRATOR CHECK ==="] + lines + ["=== END ==="]))
    sys.exit(0)


def contract_fields(path):
    sections, current = {}, None
    for line in open(path, encoding="utf-8"):
        h = re.match(r"^## (.+?)\s*$", line)
        if h:
            name = h.group(1).strip().lower()
            current = "common" if name == "the block" else name
            sections.setdefault(current, [])
            continue
        row = re.match(r"^\|\s*`([a-z_]+)`\s*\|\s*(.*?)\s*\|\s*$", line)
        if row and current:
            rule = row.group(2).lower()
            conditional = rule.startswith("optional") or rule.startswith("required when")
            sections[current].append((row.group(1), conditional))
    return sections


def parse(text):
    starts = [m.end() for m in re.finditer(r"^STAGE REPORT\s*$", text, re.M)]
    if not starts:
        return None
    body = text[starts[-1]:]
    end = re.search(r"^END STAGE REPORT\s*$", body, re.M)
    if not end:
        return None
    fields, key = {}, None
    for raw in body[:end.start()].splitlines():
        line = raw.strip()
        if not line:
            continue
        item = re.match(r"^[-*]\s+(.*)$", line)
        if item and key:
            fields[key]["items"].append(item.group(1).strip())
            continue
        kv = re.match(r"^([a-z_]+):\s*(.*)$", line)
        if kv:
            key = kv.group(1)
            fields[key] = {"value": kv.group(2).strip().strip("*").strip(), "items": []}
    return fields


def val(fields, k):
    return fields[k]["value"] if k in fields else ""


def items(fields, k):
    if k not in fields:
        return []
    f = fields[k]
    first = [f["value"]] if f["value"] and f["value"].lower() != "none" else []
    return first + f["items"]


def paths(fields, k):
    found = []
    for entry in items(fields, k):
        found += [p.strip().strip("`") for p in entry.split(",") if p.strip()]
    return found


def resolve(p):
    return p if os.path.isabs(p) else os.path.join(repo, p)


def commit_ok(sha):
    if not re.fullmatch(r"[0-9a-fA-F]{7,40}", sha):
        return False
    r = subprocess.run(["git", "-C", repo, "cat-file", "-e", f"{sha}^{{commit}}"],
                       capture_output=True)
    return r.returncode == 0


def result_of(text):
    m = RESULT_RE.match(text)
    return m.group(2) if m else None


if not os.path.isfile(report_path):
    out(["STATUS: error", "REASON: no_report_file"])
if not os.path.isfile(contracts_path):
    out(["STATUS: error", "REASON: no_contracts_file"])

fields = parse(open(report_path, encoding="utf-8").read())
if fields is None:
    out(["STATUS: none", "CONTRACT: unmet", "MISSING: STAGE REPORT — no complete STAGE REPORT ... END STAGE REPORT block"])

stage = val(fields, "stage").lower()
status = val(fields, "status").lower()
head = [f"STAGE: {stage or '-'}", f"TICKET: {val(fields, 'ticket') or '-'}"]

if stage not in STAGES:
    out(["STATUS: error", "REASON: bad_stage"] + head)

if status == "waiting":
    if not val(fields, "waiting_for"):
        out(["STATUS: waiting", "CONTRACT: unmet"] + head + ["MISSING: waiting_for — say what will wake the session"])
    out(["STATUS: waiting", "CONTRACT: skipped"] + head + [f"WAITING_FOR: {val(fields, 'waiting_for')}"])
if status == "blocked":
    if not val(fields, "needs"):
        out(["STATUS: blocked", "CONTRACT: unmet"] + head + ["MISSING: needs — name the exact step Shaked must take"])
    out(["STATUS: blocked", "CONTRACT: skipped"] + head + [f"NEEDS: {val(fields, 'needs')}"])
if status != "done":
    out(["STATUS: error", "REASON: bad_status"] + head)

sections = contract_fields(contracts_path)
if stage not in sections:
    out(["STATUS: error", "REASON: stage_not_in_contracts"] + head)

missing = []
for name, conditional in sections.get("common", []) + sections[stage]:
    if not conditional and name not in ("waiting_for", "needs") and not items(fields, name) and not val(fields, name):
        missing.append(f"{name} — missing")


def bad(name, why):
    if not any(m.startswith(name + " ") for m in missing):
        missing.append(f"{name} — {why}")


sha = val(fields, "commit")
if sha and not commit_ok(sha):
    bad("commit", f"{sha} does not resolve to a commit in the repo")

if stage == "spec":
    for p in paths(fields, "requirements"):
        if ".lattice/requirements/" not in p or not os.path.isfile(resolve(p)):
            bad("requirements", f"{p} is not a file under .lattice/requirements/")
    if "approved" in fields and val(fields, "approved").lower() != "yes":
        bad("approved", "Shaked has not approved the spec")

if stage == "design":
    doc = val(fields, "design_doc").strip("`")
    if doc:
        full = resolve(doc)
        if ".lattice/contexts/" not in doc or not os.path.isfile(full):
            bad("design_doc", f"{doc} is not a file under .lattice/contexts/")
        elif not re.search(r"status\W{0,4}\s*approved", open(full, encoding="utf-8").read(), re.I):
            bad("design_doc", f"{doc} does not say status: approved")
    for k in ("plan_eng_review", "plan_design_review", "plan_devex_review"):
        v = val(fields, k).lower()
        if v and not (v.startswith("done") or v.startswith("not-needed")):
            bad(k, "must start with done or not-needed")
    if val(fields, "plan_eng_review").lower().startswith("not-needed"):
        bad("plan_eng_review", "plan-eng-review is required for every feature")

if stage == "build":
    t = val(fields, "tests")
    if t and result_of(t) != "pass":
        bad("tests", "must read '<command> — pass (...)'")
    lint = val(fields, "lint")
    if lint and lint.lower() != "none" and result_of(lint) != "pass":
        bad("lint", "must be none or '<command> — pass'")
    if "codex" in fields and val(fields, "codex").lower() not in ("yes", "no"):
        bad("codex", "must be yes or no")
    if val(fields, "codex").lower() == "yes" and "--codex" not in val(fields, "next"):
        bad("next", "codex is yes, so the next line must ask for /fresh-review --codex")

if stage == "review":
    verdict = val(fields, "verdict")
    word = re.split(r"[\s.:,]", verdict, 1)[0] if verdict else ""
    if word == "ARCH-PENDING":
        bad("verdict", "ARCH-PENDING is a stop: report status: blocked with needs: architecture go")
    elif verdict and word not in VERDICTS:
        bad("verdict", f"'{word}' is not a fresh-review verdict")
    counts = {}
    for k in ("blockers", "should_fix"):
        v = val(fields, k)
        if v and not v.isdigit():
            bad(k, "must be a number")
        counts[k] = int(v) if v.isdigit() else 0
    if counts["blockers"] > len(items(fields, "findings")):
        bad("findings", f"{counts['blockers']} blockers but {len(items(fields, 'findings'))} finding lines")
    rep = val(fields, "report").strip("`")
    if rep and not os.path.isfile(resolve(rep)):
        bad("report", f"{rep} does not exist")
    rng = val(fields, "range")
    if rng and not re.fullmatch(r"[0-9a-fA-F]{7,40}\.\.[0-9a-fA-F]{7,40}", rng):
        bad("range", "must be <base sha>..<head sha>")
    if val(fields, "stack_unit").lower() == "yes":
        sr = val(fields, "stack_report").strip("`")
        if not sr:
            bad("stack_report", "missing — this is a stack unit")
        elif not STACK_RE.match(sr):
            bad("stack_report", "does not match the STACK REPORT shape")

if stage == "qa":
    r = val(fields, "result").lower()
    if r and r not in ("pass", "fail", "pass-with-fixes"):
        bad("result", "must be pass, fail, or pass-with-fixes")
    for p in paths(fields, "evidence"):
        if not os.path.exists(resolve(p)):
            bad("evidence", f"{p} does not exist")

if stage == "harvest":
    if val(fields, "learnings") and not val(fields, "learnings").isdigit():
        bad("learnings", "must be a number")
    if val(fields, "index") and val(fields, "index").lower() not in ("pruned", "unchanged"):
        bad("index", "must be pruned or unchanged")

if stage == "ship":
    if val(fields, "pr") and not re.search(r"github\.com/[^/\s]+/[^/\s]+/pull/\d+", val(fields, "pr")):
        bad("pr", "must be a GitHub PR URL")
    if val(fields, "head") and not re.fullmatch(r"[0-9a-fA-F]{7,40}", val(fields, "head")):
        bad("head", "must be a commit SHA")
    if val(fields, "draft") and val(fields, "draft").lower() != "yes":
        bad("draft", "the PR must open as a draft")
    if val(fields, "autofix") and val(fields, "autofix").lower() != "on":
        bad("autofix", "Auto-fix must be on")

if missing:
    out(["STATUS: done", "CONTRACT: unmet"] + head + [f"MISSING: {m}" for m in missing])
out(["STATUS: done", "CONTRACT: met"] + head)
PY
