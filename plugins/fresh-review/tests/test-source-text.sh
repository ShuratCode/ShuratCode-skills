#!/usr/bin/env bash
# test-source-text.sh — fixtures for fr-source-text.sh, the source-text test list.
#
# Traps:
# 1. Missing a test that reads code as text and asserts on it (getsource, a
#    read_text of app.py, a shell script, a `?raw` glob, readFileSync).
# 2. Flagging a test that reads data, not code: a .sql migration run on a DB, a
#    workflow loaded as YAML, a JSON contract compared with live objects.
# 3. Flagging an AST or grimp import guard. It is counted, not listed.
# 4. Flagging a CDK Template assertion, which never reads a file.
# 5. Flagging production code or context lines. Only added test lines count.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HERE/../scripts"
[ -f "$SCRIPTS/fr-source-text.sh" ] || { echo "cannot find fr-source-text.sh next to $HERE"; exit 2; }

PASS=0; FAIL=0
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

ok()  { printf '  ok   %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL %s\n       want %s / got %s\n' "$1" "$2" "$3"; FAIL=$((FAIL + 1)); }
key() { printf '%s\n' "$1" | grep "^$2:" | head -1 | sed "s/^$2: //"; }
want() { local got; got="$(key "$1" "$2")"; [ "$got" = "$3" ] && ok "$4 — $2=$3" || bad "$4" "$2=$3" "$2=$got"; }
row()  { grep -qF "$(printf '%b' "$1")" "$TMP/run/packet/source-text-tests.tsv" && ok "$2" || bad "$2" "$1" "$(cat "$TMP/run/packet/source-text-tests.tsv")"; }

scan() {
  rm -rf "$TMP/run"; mkdir -p "$TMP/run/packet"
  echo "RUN_ID='t'" > "$TMP/run/state.env"
  cat > "$TMP/run/packet/diff.patch"
  bash "$SCRIPTS/fr-source-text.sh" "$TMP/run"
}

# --- findings ----------------------------------------------------------------

OUT="$(scan <<'EOF'
diff --git a/tests/test_trigger.py b/tests/test_trigger.py
--- /dev/null
+++ b/tests/test_trigger.py
@@ -0,0 +1,6 @@
+import inspect
+from app.trigger import run_trigger
+
+def test_no_double_delivery():
+    source = inspect.getsource(run_trigger)
+    assert "output_flow_already_delivered" not in source
EOF
)"
want "$OUT" SOURCE_TEXT_FILES 1 "python getsource"
row 'tests/test_trigger.py\t5\tread' "getsource line is the read"
row 'tests/test_trigger.py\t6\tassert' "not-in line is the assert"

OUT="$(scan <<'EOF'
diff --git a/tests/test_qa_gate.py b/tests/test_qa_gate.py
--- /dev/null
+++ b/tests/test_qa_gate.py
@@ -0,0 +1,8 @@
+from pathlib import Path
+
+APP = Path(__file__).parent.parent / "src" / "app.py"
+
+def test_routes_call_gate():
+    text = APP.read_text()
+    for chunk in text.split("@app.post")[1:]:
+        assert "_launch_qa_gate(conn, caller)" in chunk
EOF
)"
want "$OUT" SOURCE_TEXT_FILES 1 "python permission by text"
row 'tests/test_qa_gate.py\t6\tread' "read_text with the path on another line"

OUT="$(scan <<'EOF'
diff --git a/tests/test_sweep.py b/tests/test_sweep.py
--- /dev/null
+++ b/tests/test_sweep.py
@@ -0,0 +1,5 @@
+from pathlib import Path
+sweep_path = Path("jobs") / "sweep.py"
+
+def test_retry_code_mirrors():
+    assert "\nRETRYABLE_EXIT_CODE = 75\n" in sweep_path.read_text()
EOF
)"
want "$OUT" SOURCE_TEXT_FILES 1 "python constant mirror"

OUT="$(scan <<'EOF'
diff --git a/tests/test_deploy_script.py b/tests/test_deploy_script.py
--- /dev/null
+++ b/tests/test_deploy_script.py
@@ -0,0 +1,5 @@
+from pathlib import Path
+
+def test_preview_guard():
+    script = Path("scripts/deploy.sh").read_text()
+    assert 'if [ "${IS_PREVIEW}" != "true" ]; then' in script
EOF
)"
want "$OUT" SOURCE_TEXT_FILES 1 "shell script by text"

OUT="$(scan <<'EOF'
diff --git a/web/src/pages/no-confirm.test.ts b/web/src/pages/no-confirm.test.ts
--- /dev/null
+++ b/web/src/pages/no-confirm.test.ts
@@ -0,0 +1,8 @@
+import { expect, it } from 'vitest';
+const sources = import.meta.glob('./*.ts', { query: '?raw', eager: true });
+
+it('never uses window.confirm', () => {
+  for (const src of Object.values(sources)) {
+    expect(src).not.toMatch(/window\.confirm\(/);
+  }
+});
EOF
)"
want "$OUT" SOURCE_TEXT_FILES 1 "ts raw glob"

OUT="$(scan <<'EOF'
diff --git a/web/test/imports.spec.ts b/web/test/imports.spec.ts
--- /dev/null
+++ b/web/test/imports.spec.ts
@@ -0,0 +1,10 @@
+import { readFileSync, readdirSync } from 'fs';
+import { join } from 'path';
+const dir = join(__dirname, '../src');
+
+it('has no forbidden imports', () => {
+  for (const file of readdirSync(dir).filter((f) => f.endsWith('.ts'))) {
+    const src = readFileSync(join(dir, file), 'utf8');
+    expect(src).not.toMatch(/from ['"]aws-sdk['"]/);
+  }
+});
EOF
)"
want "$OUT" SOURCE_TEXT_FILES 1 "ts readFileSync regex"
row 'web/test/imports.spec.ts\t7\tread' "readFileSync line is the read"

# --- not findings ------------------------------------------------------------

OUT="$(scan <<'EOF'
diff --git a/tests/test_migration.py b/tests/test_migration.py
--- /dev/null
+++ b/tests/test_migration.py
@@ -0,0 +1,7 @@
+from pathlib import Path
+MIGRATION = Path("migrations") / "0042_orders.sql"
+
+def test_migration_adds_table(conn):
+    conn.executescript(MIGRATION.read_text())
+    tables = [r[0] for r in conn.execute("select name from sqlite_master")]
+    assert "orders" in tables
EOF
)"
want "$OUT" SOURCE_TEXT_FILES 0 "sql migration run on a db"

OUT="$(scan <<'EOF'
diff --git a/tests/test_workflow.py b/tests/test_workflow.py
--- /dev/null
+++ b/tests/test_workflow.py
@@ -0,0 +1,6 @@
+import yaml
+
+def test_deploy_needs_tests():
+    wf = yaml.safe_load(open(".github/workflows/deploy.yml"))
+    assert "test" in wf["jobs"]["deploy"]["needs"]
+    assert wf["on"]["push"]["branches"] == ["main"]
EOF
)"
want "$OUT" SOURCE_TEXT_FILES 0 "yaml workflow keys"

OUT="$(scan <<'EOF'
diff --git a/tests/test_contract.py b/tests/test_contract.py
--- /dev/null
+++ b/tests/test_contract.py
@@ -0,0 +1,8 @@
+import json
+from pathlib import Path
+from app.models import Order
+
+def test_order_matches_contract():
+    contract = json.loads(Path("contracts/order.json").read_text())
+    for field in contract["fields"]:
+        assert field in Order.model_fields
EOF
)"
want "$OUT" SOURCE_TEXT_FILES 0 "json contract vs live code"

OUT="$(scan <<'EOF'
diff --git a/tests/test_layers.py b/tests/test_layers.py
--- /dev/null
+++ b/tests/test_layers.py
@@ -0,0 +1,9 @@
+import ast
+from pathlib import Path
+
+def test_domain_has_no_boto3():
+    for f in Path("src/domain").rglob("*.py"):
+        tree = ast.parse(f.read_text())
+        names = {a.name for n in ast.walk(tree) if isinstance(n, ast.Import) for a in n.names}
+        assert "boto3" not in names
+
EOF
)"
want "$OUT" SOURCE_TEXT_FILES 0 "ast import guard"
want "$OUT" LINT_GUARD_FILES 1 "ast import guard is counted"

OUT="$(scan <<'EOF'
diff --git a/tests/test_grimp.py b/tests/test_grimp.py
--- /dev/null
+++ b/tests/test_grimp.py
@@ -0,0 +1,5 @@
+import grimp
+
+def test_domain_does_not_import_infra():
+    graph = grimp.build_graph("app")
+    assert not graph.chain_exists(importer="app.domain", imported="app.infra")
EOF
)"
want "$OUT" SOURCE_TEXT_FILES 0 "grimp import guard"

OUT="$(scan <<'EOF'
diff --git a/infra/test/stack.test.ts b/infra/test/stack.test.ts
--- /dev/null
+++ b/infra/test/stack.test.ts
@@ -0,0 +1,7 @@
+import { Template } from 'aws-cdk-lib/assertions';
+
+it('creates an encrypted bucket', () => {
+  const template = Template.fromStack(stack);
+  template.hasResourceProperties('AWS::S3::Bucket', { BucketEncryption: {} });
+  expect(Object.keys(template.toJSON().Resources)).toContain('Bucket');
+});
EOF
)"
want "$OUT" SOURCE_TEXT_FILES 0 "cdk template assertion"

OUT="$(scan <<'EOF'
diff --git a/src/app/report.py b/src/app/report.py
--- a/src/app/report.py
+++ b/src/app/report.py
@@ -1,2 +1,4 @@
 import inspect
+def describe(fn):
+    return "secret" in inspect.getsource(fn)
 x = 1
diff --git a/tests/test_old.py b/tests/test_old.py
--- a/tests/test_old.py
+++ b/tests/test_old.py
@@ -1,3 +1,3 @@
 source = inspect.getsource(run_trigger)
-assert "a" not in source
+assert x == 1
EOF
)"
want "$OUT" SOURCE_TEXT_FILES 0 "production code and context lines"

OUT="$(scan </dev/null)"
want "$OUT" SOURCE_TEXT_FILES 0 "empty diff"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
