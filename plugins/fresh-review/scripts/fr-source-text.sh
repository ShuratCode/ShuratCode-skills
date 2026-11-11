#!/usr/bin/env bash
# fr-source-text.sh <RUN_DIR> — Step 4.4. Lists added tests that read code as
# text and assert on it, into $RUN_DIR/packet/source-text-tests.tsv
# (file, line, role, text). Pass I decides which are findings.
#
# Output contract (stdout):
#   === FRESH-REVIEW SOURCE TEXT ===
#   SOURCE_TEXT_FILES / SOURCE_TEXT_HITS / LINT_GUARD_FILES
#   === END ===

set -u

RUN_DIR="${1:?usage: fr-source-text.sh <RUN_DIR>}"
STATE="$RUN_DIR/state.env"
# shellcheck disable=SC1090
. "$STATE"

kv() { printf "%s='%s'\n" "$1" "$(printf '%s' "$2" | sed "s/'/'\\\\''/g")" >> "$STATE"; }

{ read -r FILES; read -r HITS; read -r LINT; } < <(
  python3 - "$RUN_DIR/packet/diff.patch" "$RUN_DIR/packet/source-text-tests.tsv" <<'PY'
import re, sys
patch, out = sys.argv[1:3]

TEST_FILE = re.compile(
    r"(^|/)(tests?|__tests__|specs?|testing)/|(^|/)test_[^/]*\.py$|_test\.(py|go)$|"
    r"\.(test|spec)\.[cm]?[jt]sx?$|(^|/)conftest\.py$|\.bats$")
CODE_EXT = r"py|pyi|ts|tsx|js|jsx|mjs|cjs|sh|bash|zsh|go|rb|java|kt|rs|php|cs|swift|scala|vue|svelte"
DATA_EXT = r"sql|json|jsonl|ya?ml|toml|csv|tsv|md|txt|html|xml|ini|cfg|env|lock|snap|graphql|proto"
CODE_LIT = re.compile(r"""['"`][^'"`]*\.(%s)['"`]|['"`/]src['"`/]""" % CODE_EXT)
DATA_LIT = re.compile(r"""\.(%s)['"`]""" % DATA_EXT)
DATA_USE = re.compile(r"\byaml\.|\bjson\.|\btoml(lib)?\.|\bcsv\.|\.execute(script|many)?\(|JSON\.parse|load_workbook")
STRONG = re.compile(r"\bgetsource\(|\bgetsourcelines\(|\?raw\b|import\.meta\.glob\(.*\braw\b")
READ = re.compile(r"\bread_text\(|\bread_bytes\(|(^|[^A-Za-z_])open\(|\breadFileSync\(|\breadFile\(|readTextFile\(")
LINT = re.compile(r"\bast\.(parse|walk|NodeVisitor)\b|\bgrimp\b|ts-morph|@babel/parser|createSourceFile\(|\besprima\b|import_?linter")
ASSERT = re.compile(
    r"^\s*assert\b.*\bin\b|\bassert(Not)?(In|Regex)\(|\.(index|find|count)\(|\bre\.(search|match|fullmatch|findall)\(|"
    r"\.(not\.)?(toMatch|toContain)\(|\.includes\(|\.indexOf\(|\.test\(")

files = {}
order = []
path = None
new_line = 0
try:
    lines = open(patch, encoding="utf-8", errors="replace").read().splitlines()
except FileNotFoundError:
    lines = []
for raw in lines:
    if raw.startswith("+++ "):
        target = raw[4:].strip()
        path = None if target == "/dev/null" else re.sub(r"^b/", "", target)
        if path is not None and path not in files:
            files[path] = []
            order.append(path)
        continue
    if raw.startswith("--- ") or raw.startswith("diff --git"):
        continue
    m = re.match(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@", raw)
    if m:
        new_line = int(m.group(1))
        continue
    if path is None:
        continue
    if raw.startswith("+"):
        files[path].append((new_line, raw[1:]))
        new_line += 1
    elif raw.startswith(" "):
        new_line += 1

rows = []
hit_files = 0
lint_files = 0
for path in order:
    if not TEST_FILE.search(path):
        continue
    added = files[path]
    if not added:
        continue
    if any(LINT.search(t) for _, t in added):
        lint_files += 1
        continue
    file_has_code = any(CODE_LIT.search(t) for _, t in added)
    reads = []
    for n, t in added:
        if STRONG.search(t):
            reads.append((n, t))
        elif READ.search(t):
            if DATA_USE.search(t) or (DATA_LIT.search(t) and not CODE_LIT.search(t)):
                continue
            if CODE_LIT.search(t) or file_has_code:
                reads.append((n, t))
    asserts = [(n, t) for n, t in added if ASSERT.search(t)]
    if not reads or not asserts:
        continue
    hit_files += 1
    for n, t in reads:
        rows.append((path, n, "read", t.strip()))
    for n, t in asserts:
        rows.append((path, n, "assert", t.strip()))

with open(out, "w", encoding="utf-8") as fh:
    for p, n, role, t in rows:
        fh.write("%s\t%d\t%s\t%s\n" % (p, n, role, t.replace("\t", " ")))
print(hit_files)
print(len(rows))
print(lint_files)
PY
)

FILES="${FILES:-0}"; HITS="${HITS:-0}"; LINT="${LINT:-0}"
kv SOURCE_TEXT_FILES "$FILES"

printf '%s\n' "=== FRESH-REVIEW SOURCE TEXT ===" \
  "SOURCE_TEXT_FILES: $FILES" \
  "SOURCE_TEXT_HITS: $HITS" \
  "LINT_GUARD_FILES: $LINT" \
  "=== END ==="
