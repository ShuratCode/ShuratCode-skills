#!/usr/bin/env bash
# validate.sh — lint the marketplace before publishing.
#
# Fails on: invalid JSON, schema violations, name/directory mismatch, missing
# description, unknown tool names, unresolvable dependencies, chat skills that
# reference Bash or local paths, and chat/Code body drift.

set -uo pipefail
cd "$(dirname "$0")/.."

FAIL=0
err()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; FAIL=1; }
ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
warn() { printf '  \033[33mwarn\033[0m  %s\n' "$*"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$*"; }

command -v python3 >/dev/null || { echo "python3 required"; exit 2; }

# --- 1. JSON well-formedness ------------------------------------------------
head_ "JSON syntax"
while IFS= read -r f; do
  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" 2>/dev/null; then
    ok "$f"
  else
    err "$f — invalid JSON"
  fi
done < <(find .claude-plugin plugins -name '*.json' 2>/dev/null | sort)

[ "$FAIL" -eq 1 ] && { echo; echo "Invalid JSON — stopping."; exit 1; }

# --- 2. Schema + cross-reference + frontmatter ------------------------------
python3 - <<'PY'
import json, os, re, sys, pathlib

fail = []
def err(m): fail.append(m); print(f"  \033[31mFAIL\033[0m  {m}")
def ok(m):  print(f"  \033[32mok\033[0m    {m}")
def warn(m):print(f"  \033[33mwarn\033[0m  {m}")
def head(m):print(f"\n\033[1m{m}\033[0m")

# Tool names valid in Claude Code skill frontmatter. Anything outside this set is
# silently ignored at runtime, which looks identical to the tool being unavailable.
VALID_TOOLS = {
    "Agent","AskUserQuestion","Bash","BashOutput","Edit","ExitPlanMode","Glob","Grep",
    "KillShell","NotebookEdit","Read","Skill","SlashCommand","Task","TodoWrite",
    "WebFetch","WebSearch","Write",
}
# Tools that parse but are not real in current Claude Code.
DEAD_TOOLS = {"Task"}

# Keys the Agent Skills spec allows for a claude.ai chat skill.
CHAT_ALLOWED_KEYS = {"name","description","license","compatibility","metadata","allowed-tools"}
CHAT_DESC_MAX = 200

def frontmatter(path):
    t = pathlib.Path(path).read_text()
    if not t.startswith("---"):
        return None, t
    _, fm, body = t.split("---", 2)
    return fm, body

# A top-level frontmatter key: starts at column 0, "key:" then EOL or space.
TOP_KEY = re.compile(r'^([A-Za-z_][A-Za-z0-9_.-]*):(?:\s+(.*))?$')

def parse_fm(fm):
    """Minimal YAML: scalars, block scalars (| >), flow lists, and '- item' lists.

    Keys are only recognised at column 0, so indented block-scalar content that
    happens to contain a colon is not mistaken for the next key.
    """
    out, key, buf, mode = {}, None, [], None

    def flush():
        if key is None: return
        out[key] = buf if mode == "list" else " ".join(x for x in buf if x).strip()

    for line in fm.splitlines():
        stripped = line.strip()
        indented = line[:1] in (" ", "\t")
        m = TOP_KEY.match(line) if not indented else None

        if m:
            flush()
            key, val = m.group(1), (m.group(2) or "").strip()
            if val in ("|", ">", "|-", ">-", "|+", ">+"):
                mode, buf = "block", []
            elif val.startswith("[") and val.endswith("]"):
                mode = "list"
                buf = [v.strip().strip('"\'') for v in val[1:-1].split(",") if v.strip()]
            elif val == "":
                mode, buf = "pending", []
            else:
                mode, buf = "scalar", [val]
            continue

        if key is None:
            continue
        if not stripped:
            if mode == "block": buf.append("")
            continue
        if stripped.startswith("- "):
            if mode in ("pending", "list"):
                mode = "list"; buf.append(stripped[2:].strip().strip('"\''))
            else:
                buf.append(stripped)
        else:
            if mode == "pending": mode = "scalar"
            buf.append(stripped)

    flush()
    return out

# ---------------------------------------------------------------- marketplace
head("Marketplace manifest")
mp = json.load(open(".claude-plugin/marketplace.json"))
for req in ("name","owner","plugins"):
    if req not in mp: err(f"marketplace.json missing required field '{req}'")
if "owner" in mp and "name" not in mp["owner"]:
    err("marketplace.json owner.name is required")
ok(f"name={mp.get('name')}  plugins={len(mp.get('plugins',[]))}")

declared = {p["name"] for p in mp.get("plugins", [])}
cross_allow = set(mp.get("allowCrossMarketplaceDependenciesOn", []))

for p in mp.get("plugins", []):
    for req in ("name","source"):
        if req not in p: err(f"marketplace plugin entry missing '{req}': {p}")
    src = p.get("source")
    if isinstance(src, str):
        if not os.path.isdir(src): err(f"{p['name']}: source path does not exist: {src}")
        else: ok(f"{p['name']} -> {src}")

# ------------------------------------------------------------------- plugins
head("Plugin manifests")
for d in sorted(pathlib.Path("plugins").iterdir()):
    if not d.is_dir(): continue
    mf = d / ".claude-plugin" / "plugin.json"
    if not mf.exists(): err(f"{d.name}: no .claude-plugin/plugin.json"); continue
    pj = json.load(open(mf))
    if "name" not in pj: err(f"{d.name}: plugin.json missing 'name'"); continue
    if pj["name"] != d.name:
        err(f"{d.name}: plugin.json name '{pj['name']}' != directory '{d.name}'")
    if d.name not in declared:
        err(f"{d.name}: exists on disk but is not listed in marketplace.json")
    # dependency resolution
    for dep in pj.get("dependencies", []):
        nm  = dep["name"] if isinstance(dep, dict) else dep.split("@")[0]
        mkt = dep.get("marketplace") if isinstance(dep, dict) else \
              (dep.split("@")[1] if "@" in dep else None)
        if mkt is None or mkt == mp["name"]:
            if nm not in declared:
                err(f"{d.name}: dependency '{nm}' not found in this marketplace")
            else:
                ok(f"{d.name} depends on {nm} (local)")
        else:
            if mkt not in cross_allow:
                err(f"{d.name}: cross-marketplace dep '{nm}@{mkt}' but '{mkt}' is not in "
                    f"allowCrossMarketplaceDependenciesOn")
            else:
                ok(f"{d.name} depends on {nm}@{mkt} (cross-marketplace, allowed)")
    if not pj.get("dependencies") and not (d / "skills").is_dir():
        err(f"{d.name}: has neither skills/ nor dependencies — installing it does nothing")

# ------------------------------------------------------------ code skills
head("Code skill frontmatter")
for sk in sorted(pathlib.Path("plugins").glob("*/skills/*/SKILL.md")):
    sdir = sk.parent.name
    fm, body = frontmatter(sk)
    if fm is None: err(f"{sk}: no YAML frontmatter"); continue
    f = parse_fm(fm)
    nm = f.get("name")
    if not nm: err(f"{sk}: missing 'name'")
    elif nm != sdir: err(f"{sk}: name '{nm}' != directory '{sdir}'")
    if not f.get("description"): err(f"{sk}: missing 'description'")
    tools = f.get("allowed-tools", [])
    if isinstance(tools, str):
        tools = [t.strip() for t in re.split(r'[,\s]+', tools) if t.strip()]
    for t in tools:
        base = t.split("(")[0]
        if base in DEAD_TOOLS:
            err(f"{sk}: allowed-tools lists '{base}', which is not a real Claude Code tool")
        elif base not in VALID_TOOLS:
            err(f"{sk}: allowed-tools lists unknown tool '{base}'")
    if "triggers" in f:
        err(f"{sk}: 'triggers' is not a supported frontmatter key (silently ignored) — "
            f"fold the phrases into 'description'")
    if not any(x in fm for x in ("name:",)): pass
    ok(f"{sk}  tools={tools or '-'}")

# --------------------------------------------------------- code script paths
head("Plugin script portability")
for sk in sorted(pathlib.Path("plugins").glob("*/skills/*/SKILL.md")):
    t = sk.read_text()
    for bad in re.findall(r'~/\.claude/skills/(?!gstack|review/|cso/|ship/)[A-Za-z0-9._-]+', t):
        err(f"{sk}: references '{bad}' — breaks once installed as a plugin; "
            f"use ${{CLAUDE_PLUGIN_ROOT}}")
    ok(f"{sk}: no self-referential ~/.claude/skills paths")

# ------------------------------------------------------------- chat skills
head("Chat skills (claude.ai constraints)")
for sk in sorted(pathlib.Path("chat-skills").glob("*/SKILL.md")):
    sdir = sk.parent.name
    fm, body = frontmatter(sk)
    if fm is None: err(f"{sk}: no YAML frontmatter"); continue
    f = parse_fm(fm)
    if f.get("name") != sdir:
        err(f"{sk}: name '{f.get('name')}' != directory '{sdir}'")
    d = f.get("description","")
    if not d: err(f"{sk}: missing 'description'")
    elif len(d) > CHAT_DESC_MAX:
        err(f"{sk}: description is {len(d)} chars, claude.ai caps it at {CHAT_DESC_MAX}")
    else: ok(f"{sk}: description {len(d)}/{CHAT_DESC_MAX} chars")
    for k in f:
        if k not in CHAT_ALLOWED_KEYS:
            err(f"{sk}: '{k}' is not in the Agent Skills spec — Code-only key in a chat skill")
    if re.search(r'\$\{CLAUDE_PLUGIN_ROOT\}|~/\.claude|/Users/', body):
        err(f"{sk}: references a local path — the chat sandbox cannot reach your machine")
    if re.search(r'\bsubagent|\bAgent tool|/lattice:|/cso\b|/review\b', body):
        err(f"{sk}: references subagents or slash commands — unavailable in chat")
    else:
        ok(f"{sk}: no Code-only capabilities referenced")

    # drift check against the Code copy
    twin = pathlib.Path(f"plugins/{sdir}/skills/{sdir}/SKILL.md")
    if twin.exists():
        _, tbody = frontmatter(twin)
        if tbody.lstrip("\n").rstrip() != body.lstrip("\n").rstrip():
            err(f"{sk}: body has drifted from {twin} — reconcile or document the fork")
        else:
            ok(f"{sk}: body matches the Code copy")

print()
if fail:
    print(f"\033[31m{len(fail)} problem(s).\033[0m")
    sys.exit(1)
print("\033[32mAll checks passed.\033[0m")
PY
rc=$?
[ "$FAIL" -eq 1 ] && exit 1
exit $rc
