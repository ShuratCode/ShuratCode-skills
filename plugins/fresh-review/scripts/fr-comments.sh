#!/usr/bin/env bash
# fr-comments.sh <RUN_DIR> — Step 4.4. Lists the comments and docstrings this
# change adds, so the report can ask for them to be dropped.
#
# Reads only the packet's diff.patch, and only its added lines. Tool directives
# (noqa, type: ignore, eslint-disable, shebangs, license headers, …) are kept out
# of the list: they change behavior, they do not explain it.
#
# Writes $RUN_DIR/packet/comments.tsv: file, start, end, kind, text (first line).
# kind is comment | inline | docstring.
#
# Output contract (stdout):
#   === FRESH-REVIEW COMMENTS ===
#   COMMENT_BLOCKS / COMMENT_LINES / COMMENT_FILES
#   === END ===

set -u

RUN_DIR="${1:?usage: fr-comments.sh <RUN_DIR>}"
STATE="$RUN_DIR/state.env"
# shellcheck disable=SC1090
. "$STATE"

kv() { printf "%s='%s'\n" "$1" "$(printf '%s' "$2" | sed "s/'/'\\\\''/g")" >> "$STATE"; }

{ read -r BLOCKS; read -r LINES; read -r FILES; } < <(
  python3 - "$RUN_DIR/packet/diff.patch" "$RUN_DIR/packet/comments.tsv" <<'PY'
import os, re, sys
patch, out = sys.argv[1:3]
HASH = {"py", "sh", "bash", "zsh", "rb", "r", "pl", "ps1", "tf", "hcl", "nix"}
SLASH = {"js", "jsx", "ts", "tsx", "mjs", "cjs", "go", "java", "kt", "kts", "scala", "rs", "c", "h",
         "cc", "cpp", "hpp", "cs", "swift", "php", "dart", "groovy", "proto", "tf", "hcl", "sc"}
DASH = {"sql", "lua", "hs"}
DIRECTIVE = re.compile(
    r"noqa|type:\s*ignore|pragma|pylint:|mypy:|pyright:|eslint|prettier-ignore|@ts-|nolint|nosec|"
    r"nosemgrep|wiz-ignore|NOSONAR|checkov:|tfsec:|trivy:|istanbul|c8 ignore|fmt:\s*(on|off|skip)|"
    r"isort:|shellcheck|^#!|-\*-|go:build|go:generate|go:embed|\+build|SPDX|[Cc]opyright|[Ll]icen[cs]e|"
    r"#\s*(end)?region|swiftlint|rubocop|jscpd|biome-ignore|deno-lint|vim:")
DEF = re.compile(r"^\s*(async\s+def|def|class)\b.*:\s*(#.*)?$")
DOC_OPEN = re.compile(r"""^[rbuRBU]{0,2}("{3}|'{3})""")

def ext_of(path):
    base = os.path.basename(path)
    return base.rsplit(".", 1)[-1].lower() if "." in base else ""

def inline_at(code, marker):
    quote = None
    i = 0
    while i < len(code):
        ch = code[i]
        if quote:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in "\"'`":
            quote = ch
        elif code.startswith(marker, i) and i > 0 and code[i - 1] in " \t":
            if marker == "//" and code[max(0, i - 1)] == ":":
                return -1
            return i
        i += 1
    return -1

rows = []
path = None
new_line = 0
prev_code = ""
in_block = False
in_doc = None
for raw in open(patch, errors="ignore"):
    line = raw.rstrip("\n")
    if line.startswith("+++ "):
        target = line[4:]
        path = None if target == "/dev/null" else target[2:] if target.startswith("b/") else target
        in_block, in_doc, prev_code = False, None, ""
        continue
    if line.startswith("--- ") or line.startswith("diff --git"):
        continue
    if line.startswith("@@"):
        m = re.search(r"\+(\d+)", line)
        new_line = int(m.group(1)) if m else 0
        in_block, in_doc, prev_code = False, None, ""
        continue
    if path is None or not line or line[0] not in "+ -":
        continue
    if line[0] == "-":
        continue
    added = line[0] == "+"
    text = line[1:]
    stripped = text.strip()
    ext = ext_of(path)
    kind = None
    note = ""
    if in_doc:
        kind = "docstring"
        if in_doc in stripped:
            in_doc = None
    elif in_block:
        kind = "comment"
        if "*/" in stripped:
            in_block = False
    elif ext == "py" and DOC_OPEN.match(stripped) and (DEF.match(prev_code) or (new_line <= 3 and not prev_code)):
        kind = "docstring"
        q = DOC_OPEN.match(stripped).group(1)
        rest = stripped[DOC_OPEN.match(stripped).end():]
        if q not in rest:
            in_doc = q
    elif ext in HASH and stripped.startswith("#"):
        kind = "comment"
    elif ext in SLASH and (stripped.startswith("//") or stripped.startswith("/*")):
        kind = "comment"
        if stripped.startswith("/*") and "*/" not in stripped:
            in_block = True
    elif ext in DASH and stripped.startswith("--"):
        kind = "comment"
    elif stripped:
        for marker, langs in (("#", HASH), ("//", SLASH), ("--", DASH)):
            at = inline_at(text, marker) if ext in langs else -1
            if at >= 0:
                kind, note = "inline", text[at:].strip()
                break
    if kind and added and not DIRECTIVE.search(note if kind == "inline" else stripped):
        note = note if kind == "inline" else stripped
        last = rows[-1] if rows else None
        if last and last[0] == path and last[2] == new_line - 1 and last[3] == kind and kind != "inline":
            last[2] = new_line
        else:
            rows.append([path, new_line, new_line, kind, note[:120]])
    if stripped and kind in (None, "inline"):
        prev_code = text
    new_line += 1

with open(out, "w") as fh:
    fh.write("file\tstart\tend\tkind\ttext\n")
    for r in rows:
        fh.write("\t".join(str(x).replace("\t", " ") for x in r) + "\n")
print(len(rows))
print(sum(r[2] - r[1] + 1 for r in rows))
print(len({r[0] for r in rows}))
PY
)

[ -n "${BLOCKS:-}" ] || { BLOCKS=0; LINES=0; FILES=0; }
kv COMMENT_BLOCKS "$BLOCKS"
kv COMMENT_LINES "$LINES"

printf '%s\n' "=== FRESH-REVIEW COMMENTS ===" \
  "COMMENT_BLOCKS: $BLOCKS" \
  "COMMENT_LINES: $LINES" \
  "COMMENT_FILES: $FILES" \
  "=== END ==="
