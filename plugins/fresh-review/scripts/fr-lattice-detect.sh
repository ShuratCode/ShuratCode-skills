#!/usr/bin/env bash
# fr-lattice-detect.sh <RUN_DIR> — Step 4.4. Decides whether this change has a
# lattice design or context document, which is what gates Pass A (lattice).
#
# A match is one of, in order:
#   diff_touches_context   the diff itself adds or edits a doc under .lattice/{contexts,context,requirements,designs}
#   branch_match           a doc's frontmatter `branch:` names this branch (or the PR head branch)
#   names_changed_files    a doc names at least two of the changed files (one, when only one changed)
#
# Reads only file names, frontmatter, and grep hits. Never prints doc content.
#
# Output contract (stdout):
#   === FRESH-REVIEW LATTICE DETECT ===
#   LATTICE_CONTEXT: yes | no
#   LATTICE_REASON: <slug>
#   LATTICE_DOC: <repo-relative path | none>
#   === END ===

set -u

RUN_DIR="${1:?usage: fr-lattice-detect.sh <RUN_DIR>}"
STATE="$RUN_DIR/state.env"
# shellcheck disable=SC1090
. "$STATE"

kv() { printf "%s='%s'\n" "$1" "$(printf '%s' "$2" | sed "s/'/'\\\\''/g")" >> "$STATE"; }

HEAD_BRANCH=""
[ -f "$RUN_DIR/pr.json" ] && HEAD_BRANCH=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("headRefName") or "")' "$RUN_DIR/pr.json" 2>/dev/null)

{ read -r FOUND; read -r REASON; read -r DOC; } < <(
  python3 - "${SOURCE_ROOT:-$REPO_ROOT}" "$RUN_DIR/packet/files.txt" "${BRANCH:-}" "$HEAD_BRANCH" <<'PY'
import os, re, sys
root, files_txt, branch, head_branch = sys.argv[1:5]
DOC_DIRS = ("contexts", "context", "requirements", "designs", "design")
changed = []
for line in open(files_txt, errors="ignore"):
    parts = line.rstrip("\n").split("\t")
    if len(parts) >= 2:
        changed.append(parts[-1])

def emit(found, reason, doc):
    print("yes" if found else "no"); print(reason); print(doc or "none"); sys.exit(0)

for path in changed:
    segs = path.split("/")
    if ".lattice" in segs:
        i = segs.index(".lattice")
        if i + 1 < len(segs) and segs[i + 1] in DOC_DIRS and path.endswith(".md"):
            emit(True, "diff_touches_context", path)

lattice_dirs = []
for dirpath, dirnames, _ in os.walk(root):
    rel = os.path.relpath(dirpath, root)
    depth = 0 if rel == "." else rel.count(os.sep) + 1
    dirnames[:] = [d for d in dirnames if d not in (".git", "node_modules", ".venv", "venv", ".claude", ".fresh-review")]
    if ".lattice" in dirnames:
        lattice_dirs.append(os.path.join(dirpath, ".lattice"))
    if depth >= 3:
        dirnames[:] = []
if not lattice_dirs:
    emit(False, "no_lattice_dir", None)

branches = {b for b in (branch, head_branch) if b}
docs = []
for ld in lattice_dirs:
    for sub in DOC_DIRS:
        base = os.path.join(ld, sub)
        for dirpath, _, names in os.walk(base):
            docs += [os.path.join(dirpath, n) for n in names if n.endswith(".md")]
if not docs:
    emit(False, "no_context_docs", None)

def frontmatter_branch(path):
    try:
        text = open(path, errors="ignore").read(4000)
    except OSError:
        return ""
    if not text.startswith("---"):
        return ""
    m = re.search(r"^branch:\s*['\"]?([^\s'\"]+)", text.split("\n---", 1)[0], re.M)
    return m.group(1) if m else ""

for doc in docs:
    b = frontmatter_branch(doc)
    if b and b in branches:
        emit(True, "branch_match", os.path.relpath(doc, root))

need = 1 if len(changed) == 1 else 2
best, best_hits = None, 0
for doc in docs:
    project = os.path.relpath(os.path.dirname(doc).split(os.sep + ".lattice")[0], root)
    try:
        text = open(doc, errors="ignore").read()
    except OSError:
        continue
    hits = 0
    for path in changed:
        if "/" not in path or "/.lattice/" in "/" + path:
            continue
        local = path[len(project) + 1:] if project != "." and path.startswith(project + "/") else path
        if path in text or ("/" in local and local in text):
            hits += 1
    if hits > best_hits:
        best, best_hits = doc, hits
if best and best_hits >= need:
    emit(True, "names_changed_files", os.path.relpath(best, root))
emit(False, "no_matching_doc", None)
PY
)

[ -n "${FOUND:-}" ] || { FOUND=no; REASON=detect_failed; DOC=none; }
kv LATTICE_CONTEXT "$FOUND"
kv LATTICE_REASON "$REASON"

printf '%s\n' "=== FRESH-REVIEW LATTICE DETECT ===" \
  "LATTICE_CONTEXT: $FOUND" \
  "LATTICE_REASON: $REASON" \
  "LATTICE_DOC: $DOC" \
  "=== END ==="
