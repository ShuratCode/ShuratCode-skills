#!/usr/bin/env bash
# test-comments.sh — fixtures for fr-comments.sh, the "drop the comments" list.
#
# Traps:
# 1. Flagging tool directives (noqa, eslint-disable, type: ignore). They change
#    behavior; dropping them breaks the build.
# 2. Flagging a triple-quoted string that is data (a SQL query) as a docstring.
# 3. Flagging a URL's `//` or `#fragment` as an inline comment.
# 4. Flagging removed or context lines. Only what this change adds counts.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HERE/../scripts"

PASS=0; FAIL=0
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

ok()  { printf '  ok   %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL %s\n       want %s / got %s\n' "$1" "$2" "$3"; FAIL=$((FAIL + 1)); }
key() { printf '%s\n' "$1" | grep "^$2:" | head -1 | sed "s/^$2: //"; }
want() { local got; got="$(key "$1" "$2")"; [ "$got" = "$3" ] && ok "$4 — $2=$3" || bad "$4" "$2=$3" "$2=$got"; }
row()  { grep -qF "$(printf '%b' "$1")" "$TMP/run/packet/comments.tsv" && ok "$2" || bad "$2" "$1" "$(cat "$TMP/run/packet/comments.tsv")"; }
norow(){ grep -qF "$(printf '%b' "$1")" "$TMP/run/packet/comments.tsv" && bad "$2" "no row for $1" "$(cat "$TMP/run/packet/comments.tsv")" || ok "$2"; }

scan() {
  rm -rf "$TMP/run"; mkdir -p "$TMP/run/packet"
  echo "RUN_ID='t'" > "$TMP/run/state.env"
  cat > "$TMP/run/packet/diff.patch"
  bash "$SCRIPTS/fr-comments.sh" "$TMP/run"
}

OUT="$(scan <<'EOF'
diff --git a/app/svc.py b/app/svc.py
--- a/app/svc.py
+++ b/app/svc.py
@@ -1,4 +1,15 @@
 import os
-# an old comment that is removed
+# Load the config first
+# then the rest
+def load(path):  # noqa: E501
+    """Load a thing.
+
+    More words.
+    """
+    url = "http://x.com/#frag"
+    x = 1  # set x
+    q = """
+    select 1
+    """
+    return x  # type: ignore
 # a context comment
diff --git a/web/a.ts b/web/a.ts
--- a/web/a.ts
+++ b/web/a.ts
@@ -5,2 +5,5 @@
 const a = 1;
+// helper
+const u = "https://x.com"; // eslint-disable-line
+const b = 2; // two
EOF
)"

want "$OUT" COMMENT_BLOCKS 5 "block count"
want "$OUT" COMMENT_FILES 2 "file count"
row 'app/svc.py\t2\t3\tcomment' "consecutive full-line comments merge into one block"
row 'app/svc.py\t5\t8\tdocstring' "a def docstring is one block"
row 'app/svc.py\t10\t10\tinline\t# set x' "an inline comment"
row 'web/a.ts\t6\t6\tcomment' "a // comment"
row 'web/a.ts\t8\t8\tinline\t// two' "a trailing // comment"
norow 'noqa' "noqa directive is kept"
norow 'type: ignore' "type: ignore directive is kept"
norow 'eslint' "eslint directive is kept"
norow '#frag' "a URL fragment is not a comment"
norow 'select 1' "a SQL string is not a docstring"
norow 'old comment' "a removed comment is not listed"
norow 'context comment' "a context line is not listed"

OUT="$(scan <<'EOF'
diff --git a/README.md b/README.md
--- a/README.md
+++ b/README.md
@@ -1 +1,2 @@
 # Title
+# Another heading
EOF
)"
want "$OUT" COMMENT_BLOCKS 0 "markdown headings are not code comments"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
