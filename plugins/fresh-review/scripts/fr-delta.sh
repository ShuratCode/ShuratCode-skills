#!/usr/bin/env bash
# fr-delta.sh <RUN_DIR> [--choice delta|full] — Step 1.6, pr-remote only.
#
# Output contract (stdout):
#   === FRESH-REVIEW DELTA ===
#   DELTA: off | applied | ask | full | none
#   DELTA_REASON: <slug>                        (ask | full | none)
#   DELTA_SOURCE: record | runs_index | none
#   PRIOR_REVIEW: <run id> | none
#   PRIOR_HEAD / PRIOR_VERDICT / PRIOR_BLOCKERS / PRIOR_RISK / PRIOR_COVERAGE / PRIOR_ARCH_GATE
#                                               (when a prior review exists)
#   DELTA_KIND: fast_forward | rebased          (applied)
#   DIFF_BASE / DIFF_CMD / DELTA_HEAD           (applied)
#   === END ===

set -u

USAGE="usage: fr-delta.sh <RUN_DIR> [--choice delta|full]"
RUN_DIR="${1:?$USAGE}"
CHOICE=""
if [ $# -gt 1 ]; then
  [ "$2" = --choice ] || { echo "$USAGE" >&2; exit 2; }
  CHOICE="${3:-}"
  case "$CHOICE" in delta|full) : ;; *) echo "$USAGE" >&2; exit 2 ;; esac
fi
STATE="$RUN_DIR/state.env"
# shellcheck disable=SC1090
. "$STATE"

kv() { printf "%s='%s'\n" "$1" "$(printf '%s' "$2" | sed "s/'/'\\\\''/g")" >> "$STATE"; }

RECORD="$LOG_DIR/reviews/$REVIEW_KEY.json"
REF_ROOT="refs/fresh-review/reviewed/$REVIEW_KEY"
PRIOR="$RUN_DIR/raw/delta-prior.json"
PRIOR_RUN=none
SOURCE=none

report_roots() {
  printf '%s\n' "$REPORT_DIR"
  git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | while IFS= read -r wt; do
    git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null | sed 's|$|/fresh-review|'
    [ "$wt" = "${PR_WT:-}" ] && continue
    case "${wt##*/}" in prwt-*|fresh-review-prwt-*) continue ;; esac
    printf '%s\n' "$wt/.fresh-review"
  done
}

FIELDS=$(python3 - "$RECORD" "$LOG_DIR/runs.jsonl" "${PR_NUMBER:-}" "${SINCE_PR:-}" \
    "$LOG_DIR/reviews/$REVIEW_KEY.architecture.md" "$PRIOR" "$(report_roots)" <<'PY'
import csv, json, os, subprocess, sys
record_path, index_path, pr_number, since_pr, arch_path, out, roots = sys.argv[1:8]
roots = [line for line in roots.splitlines() if line]
required = ("severity", "file", "line", "category", "problem", "fix")
verdicts = ("APPROVE", "APPROVE-WITH-COMMENTS", "REQUEST-CHANGES")
columns = ("bucket", "severity", "location", "finding")

def regular_file(path):
    return bool(path) and os.path.isfile(path) and not os.path.islink(path)

def run_dir_of(run_id):
    for root in roots:
        run_dir = os.path.join(root, "runs", run_id)
        if os.path.isdir(run_dir) and not os.path.islink(run_dir) and \
                os.path.realpath(run_dir).startswith(os.path.realpath(root) + os.sep):
            return run_dir
    return None

def architecture_in(run_dir):
    path = os.path.join(run_dir, "raw", "architecture.md") if run_dir else None
    return path if regular_file(path) else None

def gate_of(entry):
    gate = (entry.get("architecture") or {}).get("gate") or "none"
    return "approved" if gate in ("approved", "skipped", "carried") else gate

def from_record():
    try:
        record = json.load(open(record_path))
    except Exception:
        return None
    blockers = record.get("blockers")
    if not record.get("run_id") or not isinstance(blockers, list):
        return None
    if any(not isinstance(b, dict) or any(k not in b for k in required) for b in blockers):
        return None
    gate, architecture = record.get("arch_gate"), arch_path if regular_file(arch_path) else None
    if gate is None:
        entry = next((e for e in reversed(index_entries()) if e.get("run_id") == record["run_id"]), {})
        gate, architecture = gate_of(entry), architecture_in(run_dir_of(record["run_id"]))
    return {"source": "record", "run_id": record["run_id"], "verdict": record.get("verdict"),
            "head": record.get("head"), "base": record.get("base"),
            "coverage": record.get("coverage"), "risk": record.get("risk"),
            "arch_gate": gate or "none", "architecture": architecture, "blockers": blockers}

def index_entries():
    try:
        lines = open(index_path).read().splitlines()
    except OSError:
        return []
    entries = []
    for line in lines:
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if isinstance(entry, dict):
            entries.append(entry)
    return entries

def usable(entry):
    pr = entry.get("pr") or {}
    delta = entry.get("delta") or {}
    gate = (entry.get("architecture") or {}).get("gate")
    return (entry.get("mode") == "pr" and str(pr.get("number")) == pr_number
            and pr.get("head") and entry.get("diff_base") and entry.get("run_id")
            and entry.get("verdict") in verdicts and not delta.get("applied")
            and gate not in ("rejected", "pending")
            and (entry.get("stack") or {}).get("prs", [int(pr_number)]) == [int(pr_number)])

def has_commits(entry):
    return all(subprocess.run(["git", "cat-file", "-e", f"{sha}^{{commit}}"],
                              capture_output=True).returncode == 0
               for sha in (entry["pr"]["head"], entry["diff_base"]))

def coverage_of(entry):
    lenses = ("lattice", "cso", "review", "codex", "fix-check", "static-analysis")
    status = {p.get("name"): p.get("status") for p in entry.get("passes") or []}
    needed = {"lattice", "cso", "review"} | ({"codex"} if entry.get("codex_requested") else set())
    lost = any(status.get(name) != "ok" for name in needed) or \
        any(status[name] != "ok" for name in lenses if name in status) or \
        (entry.get("architecture") or {}).get("gate") == "failed"
    return "reduced" if lost else "full"

def blockers_from(run_dir):
    path = os.path.join(run_dir, "findings.tsv")
    if not regular_file(path):
        return None
    reader = csv.DictReader(open(path, newline=""), delimiter="\t", quoting=csv.QUOTE_NONE)
    if any(k not in (reader.fieldnames or []) for k in columns):
        return None
    rows = list(reader)
    blockers = []
    for row in rows:
        if (row.get("bucket") or "").strip() != "1":
            continue
        path, _, line = (row.get("location") or "").rpartition(":")
        if not line.isdigit():
            path, line = row.get("location") or "-", "-"
        blockers.append({"severity": row["severity"], "file": path, "line": line,
                         "category": row.get("category") or "-", "problem": row["finding"],
                         "fix": row.get("fix") or "not in the run index"})
    return blockers

def from_index():
    if since_pr or not pr_number:
        return None
    candidates = [e for e in index_entries() if usable(e)]
    if not candidates:
        return None
    entry = next((e for e in reversed(candidates) if has_commits(e)), candidates[-1])
    run_dir = run_dir_of(entry["run_id"])
    return {"source": "runs_index", "run_id": entry["run_id"], "verdict": entry["verdict"],
            "head": entry["pr"]["head"], "base": entry["diff_base"],
            "coverage": coverage_of(entry), "risk": entry.get("risk"),
            "arch_gate": gate_of(entry), "architecture": architecture_in(run_dir),
            "blockers": blockers_from(run_dir) if run_dir else None}

if os.path.exists(record_path):
    prior = from_record()
    state = "ok" if prior else "invalid"
else:
    prior = from_index()
    state = "ok" if prior else "missing"
print(state)
if prior:
    json.dump(prior, open(out, "w"), indent=1)
    blockers = prior["blockers"]
    for key in ("source", "run_id", "verdict", "head", "base", "coverage", "risk", "arch_gate"):
        print(prior.get(key) or "-")
    print("unknown" if blockers is None else len(blockers))
PY
)
{ read -r PRIOR_STATE; read -r SOURCE; read -r PRIOR_RUN; read -r PRIOR_VERDICT; read -r SOURCE_HEAD
  read -r SOURCE_BASE; read -r PRIOR_COVERAGE; read -r PRIOR_RISK; read -r PRIOR_ARCH_GATE
  read -r PRIOR_BLOCKERS; } <<< "$FIELDS"
[ "$PRIOR_STATE" = ok ] || { SOURCE=none; PRIOR_RUN=none; }

commit_of() { git rev-parse --verify -q "$1^{commit}" 2>/dev/null || echo ""; }
if [ "$SOURCE" = runs_index ]; then
  PRIOR_HEAD=$(commit_of "$SOURCE_HEAD")
  PRIOR_BASE=$(commit_of "$SOURCE_BASE")
else
  PRIOR_HEAD=$(commit_of "$REF_ROOT/head")
  PRIOR_BASE=$(commit_of "$REF_ROOT/base")
fi

finish() {
  local delta="$1" reason="${2:-}"
  kv DELTA "$delta"
  kv DELTA_REASON "$reason"
  kv DELTA_SOURCE "$SOURCE"
  {
    echo "=== FRESH-REVIEW DELTA ==="
    echo "DELTA: $delta"
    [ -n "$reason" ] && echo "DELTA_REASON: $reason"
    echo "DELTA_SOURCE: $SOURCE"
    echo "PRIOR_REVIEW: $PRIOR_RUN"
    if [ "$PRIOR_RUN" != none ]; then
      echo "PRIOR_HEAD: ${PRIOR_HEAD:-missing}"
      echo "PRIOR_VERDICT: $PRIOR_VERDICT"
      echo "PRIOR_BLOCKERS: $PRIOR_BLOCKERS"
      echo "PRIOR_RISK: $PRIOR_RISK"
      echo "PRIOR_COVERAGE: $PRIOR_COVERAGE"
      echo "PRIOR_ARCH_GATE: $PRIOR_ARCH_GATE"
    fi
    if [ "$delta" = applied ]; then
      echo "DELTA_KIND: $DELTA_KIND"
      echo "DIFF_BASE: $DELTA_BASE"
      echo "DIFF_CMD: $DIFF_CMD"
      echo "DELTA_HEAD: $DELTA_HEAD"
    fi
    echo "=== END ==="
  }
  exit 0
}

gap() {
  [ "$CHOICE" = delta ] && return 0
  [ "$CHOICE" = full ] && finish full "$1"
  finish ask "$1"
}

[ "${DELTA_REQUESTED:-0}" = 1 ] || finish off
[ "$PRIOR_STATE" != missing ] || { [ -n "$CHOICE" ] && finish full no_prior_review; finish ask no_prior_review; }
[ "$PRIOR_STATE" = ok ] || finish full record_invalid
[ -n "$PRIOR_HEAD" ] && [ -n "$PRIOR_BASE" ] || finish full prior_head_missing
[ "$SOURCE" = runs_index ] || { [ "$SOURCE_HEAD" = "$PRIOR_HEAD" ] && [ "$SOURCE_BASE" = "$PRIOR_BASE" ]; } \
  || finish full record_mismatch

mkdir -p "$RUN_DIR/delta"
if [ "$PRIOR_ARCH_GATE" = approved ]; then
  ARCH_SRC=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("architecture") or "")' "$PRIOR")
  [ -n "$ARCH_SRC" ] && cp "$ARCH_SRC" "$RUN_DIR/delta/prior-architecture.md"
fi
kv DELTA_PRIOR_ARCH_GATE "$PRIOR_ARCH_GATE"

[ "$PRIOR_HEAD" != "$PR_HEAD" ] || [ "$PRIOR_BASE" != "$PR_MERGE_BASE" ] || finish none no_new_commits

MERGED=$(git merge-tree --write-tree --merge-base "$PRIOR_BASE" "$PR_MERGE_BASE" "$PRIOR_HEAD" \
  2>"$RUN_DIR/raw/delta-replay.err")
RC=$?
[ "$RC" -eq 1 ] && finish full replay_conflict
[ "$RC" -eq 0 ] || finish full replay_failed
REPLAYED_TREE=$(printf '%s\n' "$MERGED" | head -1)

if [ "$REPLAYED_TREE" = "$(git rev-parse "$PR_HEAD^{tree}")" ]; then
  [ "$PRIOR_BASE" = "$PR_MERGE_BASE" ] && finish none no_net_change
  [ "$PRIOR_BLOCKERS" != unknown ] || gap prior_blockers_unknown
  [ "$PRIOR_BLOCKERS" = 0 ] || [ "$PRIOR_BLOCKERS" = unknown ] || finish full rebased_with_blockers
  finish none rebase_only
fi

[ "$PRIOR_COVERAGE" = full ] || gap prior_reduced_coverage
[ "$PRIOR_BLOCKERS" != unknown ] || gap prior_blockers_unknown

python3 - "$PRIOR" "$RUN_DIR/delta/prior-blockers.md" <<'PY' || finish full record_invalid
import json, sys
prior = json.load(open(sys.argv[1]))
lines = [f"# Blockers from the last review — run {prior['run_id']}, "
         f"PR head {prior['head']}, verdict {prior['verdict']}", ""]
if prior["blockers"] is None:
    lines.append("unknown — the last review's findings were pruned; its blockers cannot be checked")
for i, b in enumerate(prior["blockers"] or [], 1):
    lines.append(f"B{i}. {b['severity']} {b['file']}:{b['line']} [{b['category']}] {b['problem']}")
    lines.append(f"    fix asked: {b['fix']}")
if prior["blockers"] == []:
    lines.append("none")
open(sys.argv[2], "w").write("\n".join(lines) + "\n")
PY

export GIT_AUTHOR_NAME=fresh-review GIT_AUTHOR_EMAIL=fresh-review@localhost
export GIT_COMMITTER_NAME=fresh-review GIT_COMMITTER_EMAIL=fresh-review@localhost
DELTA_BASE=$(git commit-tree --no-gpg-sign "$REPLAYED_TREE" -p "$PR_MERGE_BASE" \
  -m "fresh-review: PR as last reviewed at $PRIOR_HEAD, on its current base") || finish full replay_failed
DELTA_HEAD=$(git commit-tree --no-gpg-sign "$PR_HEAD^{tree}" -p "$DELTA_BASE" \
  -m "fresh-review: changes since the last review") || finish full replay_failed

git -c core.hooksPath=/dev/null -C "$PR_WT" checkout --quiet --detach "$DELTA_HEAD" \
  2>"$RUN_DIR/raw/delta-checkout.err" || finish full worktree_failed

DELTA_KIND=rebased
if [ "$PRIOR_BASE" = "$PR_MERGE_BASE" ] && git merge-base --is-ancestor "$PRIOR_HEAD" "$PR_HEAD"; then
  DELTA_KIND=fast_forward
fi
DIFF_CMD="git diff $DELTA_BASE $DELTA_HEAD"

kv DIFF_BASE "$DELTA_BASE"
kv DIFF_CMD "$DIFF_CMD"
kv DELTA_HEAD "$DELTA_HEAD"
kv DELTA_KIND "$DELTA_KIND"
kv DELTA_PRIOR_RUN "$PRIOR_RUN"
kv DELTA_PRIOR_HEAD "$PRIOR_HEAD"
kv DELTA_PRIOR_VERDICT "$PRIOR_VERDICT"
kv DELTA_PRIOR_BLOCKERS "$PRIOR_BLOCKERS"
kv DELTA_PRIOR_RISK "$PRIOR_RISK"
kv DELTA_PRIOR_COVERAGE "$PRIOR_COVERAGE"
finish applied
