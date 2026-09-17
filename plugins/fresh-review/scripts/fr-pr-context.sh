#!/usr/bin/env bash
# fr-pr-context.sh <RUN_DIR> — Step 4.7. Gathers the PR's own context — its
# description, its human discussion, and any static-analysis bot findings
# (Wiz, Snyk, SonarCloud, CodeQL, Semgrep, …) — to disk, for the PRODUCER side
# only.
#
# This is the one place the skill deliberately reads intent, and it is safe
# precisely because nothing it writes ever reaches the isolated passes. Two jobs
# need this context and neither is a critic:
#   - Triage (Step 7) must not re-raise a finding the PR already discussed and
#     dismissed, and a bucket-2 "by design" may cite a decision made in the
#     thread.
#   - The static-analysis verification (Pass W, Step 5) must know which tool
#     findings were posted so it can check each was fixed, suppressed, or
#     dismissed rather than silently ignored.
# The critic and narrator passes NEVER see any of this: everything lands under
# $RUN_DIR/pr-context/, which the fan-out does not hand them and their
# forbidden-reads list names explicitly. A narrator that read the description
# would produce a restatement of the author's claim, which is the one thing the
# isolation exists to prevent.
#
# Runs whenever a PR is discoverable: PR_NUMBER is already set in pr-remote; on
# your own branch it is discovered from the branch's open PR. No PR, or no gh, is
# a clean skip — never an error, because the default pre-commit run has no PR and
# must not be blocked by its absence.
#
# Output contract (stdout):
#   === FRESH-REVIEW PR CONTEXT ===
#   PR_CONTEXT: present | none | unavailable
#   REASON: <slug>                       (only when none/unavailable)
#   PR_NUMBER / PR_URL / PR_STATE
#   COMMENT_COUNT / REVIEW_COUNT / THREAD_COUNT / DISCUSSION_LINES
#   SA_PRESENT: yes | no
#   SA_TOOL: <comma list, or none>
#   SA_SIGNAL: <count of tool comments/threads/checks>
#   === END ===

set -u

RUN_DIR="${1:?usage: fr-pr-context.sh <RUN_DIR>}"
STATE="$RUN_DIR/state.env"
# shellcheck disable=SC1090
. "$STATE"

kv() { printf "%s='%s'\n" "$1" "$(printf '%s' "$2" | sed "s/'/'\\\\''/g")" >> "$STATE"; }

CTX_DIR="$RUN_DIR/pr-context"
mkdir -p "$CTX_DIR"
ERR="$RUN_DIR/raw/pr-context.err"

# A skip records "no static-analysis material to verify" as well as "no PR
# context to triage against", so downstream steps have both keys either way.
skip() { # status  reason
  kv PR_CONTEXT "$1"
  kv SA_PRESENT "no"
  kv SA_TOOL "none"
  kv SA_SIGNAL "0"
  printf '%s\n' "=== FRESH-REVIEW PR CONTEXT ===" "PR_CONTEXT: $1"
  [ -n "${2:-}" ] && printf 'REASON: %s\n' "$2"
  printf '%s\n' "SA_PRESENT: no" "SA_TOOL: none" "SA_SIGNAL: 0" "=== END ==="
  exit 0
}

command -v gh >/dev/null 2>&1 || skip unavailable gh_missing

# Discover the PR. pr-remote already resolved PR_NUMBER; otherwise ask gh for the
# open PR of the current branch. A repo with no PR for this branch is the normal
# pre-commit case and is a clean `none`, not a failure.
PR_NUM="${PR_NUMBER:-}"
if [ -z "$PR_NUM" ]; then
  gh pr view --json number,url,state,title,body,comments,reviews,headRefOid \
    > "$CTX_DIR/pr.json" 2>"$ERR" || skip none no_pr_for_branch
  PR_NUM=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("number") or "")' \
    "$CTX_DIR/pr.json" 2>/dev/null)
  [ -n "$PR_NUM" ] || skip none no_pr_for_branch
else
  gh pr view "$PR_NUM" --json number,url,state,title,body,comments,reviews,headRefOid \
    > "$CTX_DIR/pr.json" 2>"$ERR" || skip unavailable gh_pr_view_failed
fi

SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
[ -n "$SLUG" ] || skip unavailable no_repo_slug

# Inline review threads (line comments) are a separate endpoint from the issue
# comments `gh pr view` returns — and they are exactly where a human reply that
# dismisses a bot finding lives, so they are load-bearing for Pass W, not
# optional. A failure here degrades to an empty array rather than aborting the
# whole gather.
gh api "repos/$SLUG/pulls/$PR_NUM/comments" --paginate \
  > "$CTX_DIR/review-comments.json" 2>>"$ERR" || printf '[]\n' > "$CTX_DIR/review-comments.json"

# Some analyzers (CodeQL and other SARIF tools especially) report as check runs
# on the head commit rather than as comments. Fetch them so Pass W sees those too.
HEAD_SHA="${PR_HEAD:-}"
[ -z "$HEAD_SHA" ] && HEAD_SHA=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("headRefOid") or "")' \
  "$CTX_DIR/pr.json" 2>/dev/null)
if [ -n "$HEAD_SHA" ]; then
  gh api "repos/$SLUG/commits/$HEAD_SHA/check-runs" \
    > "$CTX_DIR/check-runs.json" 2>>"$ERR" || printf '{"check_runs":[]}\n' > "$CTX_DIR/check-runs.json"
else
  printf '{"check_runs":[]}\n' > "$CTX_DIR/check-runs.json"
fi

# Reduce the raw JSON into the two producer artifacts (body.md, discussion.md)
# and the one Pass-W artifact (sa-findings.md), and print the counts the
# orchestrator needs. Content never crosses back through stdout — only integers
# and the detected tool names.
SUMMARY=$(python3 - "$CTX_DIR" <<'PY'
import json, os, re, sys

ctx = sys.argv[1]

def load(name, default):
    try:
        with open(os.path.join(ctx, name)) as fh:
            return json.load(fh)
    except Exception:
        return default

pr = load("pr.json", {})
threads = load("review-comments.json", [])
checks = load("check-runs.json", {}).get("check_runs", []) or []

# Security / code-analysis tools whose PR comments and checks Pass W must verify.
# Deliberately excludes dependency-update bots (dependabot, renovate) — those
# raise PRs, not findings to disposition.
TOOL_RX = re.compile(
    r"wiz|snyk|sonar|codeql|github-advanced-security|semgrep|checkmarx|fortify|"
    r"deepsource|codacy|coverity|trivy|aqua|prisma|mend|whitesource|veracode|"
    r"gitguardian|ggshield|bandit|bearer|kics|tfsec|checkov",
    re.I,
)

def actor(obj, *keys):
    for k in keys:
        v = obj.get(k)
        if isinstance(v, dict):
            return v.get("login") or v.get("name") or ""
        if isinstance(v, str) and v:
            return v
    return ""

def is_bot(login):
    return login.lower().endswith("[bot]")

def tool_match(*fields):
    for f in fields:
        if f and TOOL_RX.search(f):
            m = TOOL_RX.search(f)
            return m.group(0).lower()
    return ""

tools = set()
sa_blocks = []
disc_lines = []

body = pr.get("body") or ""
with open(os.path.join(ctx, "body.md"), "w") as fh:
    fh.write(body.strip() + "\n" if body.strip() else "(no description)\n")

comments = pr.get("comments") or []
for c in comments:
    login = actor(c, "author")
    tool = tool_match(login, c.get("body", ""))
    line = f"[comment] {login or 'unknown'}: {(c.get('body') or '').strip()}"
    disc_lines.append(line)
    if tool:
        tools.add(tool)
        sa_blocks.append(f"### tool comment — {login} ({tool})\n{(c.get('body') or '').strip()}\n")

reviews = pr.get("reviews") or []
for r in reviews:
    login = actor(r, "author")
    st = r.get("state") or ""
    b = (r.get("body") or "").strip()
    if b:
        disc_lines.append(f"[review:{st}] {login or 'unknown'}: {b}")
    tool = tool_match(login, b)
    if tool and b:
        tools.add(tool)
        sa_blocks.append(f"### tool review — {login} ({tool})\n{b}\n")

# Inline threads: group replies under their root so a human dismissal of a bot
# finding travels with the finding it dismisses.
by_id = {t.get("id"): t for t in threads if isinstance(t, dict)}
roots = {}
for t in threads:
    if not isinstance(t, dict):
        continue
    root = t.get("in_reply_to_id") or t.get("id")
    roots.setdefault(root, []).append(t)

thread_count = 0
for root_id, msgs in roots.items():
    thread_count += 1
    head = by_id.get(root_id, msgs[0])
    hlogin = actor(head, "user", "author")
    path = head.get("path") or ""
    ln = head.get("line") or head.get("original_line") or ""
    loc = f"{path}:{ln}" if path else ""
    tool = tool_match(hlogin, head.get("body", ""))
    rendered = []
    for m in msgs:
        mlogin = actor(m, "user", "author")
        rendered.append(f"  - {mlogin or 'unknown'}: {(m.get('body') or '').strip()}")
    disc_lines.append(f"[thread] {loc} {hlogin or 'unknown'}:\n" + "\n".join(rendered))
    if tool:
        tools.add(tool)
        sa_blocks.append(
            f"### tool thread — {hlogin} ({tool}) at {loc or 'unknown location'}\n"
            + "\n".join(rendered) + "\n"
        )

check_hits = 0
for ch in checks:
    name = ch.get("name") or ""
    app = ch.get("app") or {}
    app_slug = app.get("slug") or app.get("name") or "" if isinstance(app, dict) else ""
    tool = tool_match(name, app_slug)
    if not tool:
        continue
    concl = ch.get("conclusion") or ch.get("status") or ""
    out = ch.get("output") or {}
    title = out.get("title") or ""
    summary = out.get("summary") or ""
    tools.add(tool)
    check_hits += 1
    sa_blocks.append(
        f"### tool check — {name} ({tool}) conclusion={concl}\n{title}\n{summary}\n"
    )

with open(os.path.join(ctx, "discussion.md"), "w") as fh:
    fh.write("\n\n".join(disc_lines).strip() + "\n" if disc_lines else "(no discussion)\n")

with open(os.path.join(ctx, "sa-findings.md"), "w") as fh:
    fh.write("\n".join(sa_blocks).strip() + "\n" if sa_blocks else "(no static-analysis findings on this PR)\n")

sa_signal = len(sa_blocks)
disc_line_count = sum(len(x.splitlines()) for x in disc_lines)
print(f"COMMENT_COUNT={len(comments)}")
print(f"REVIEW_COUNT={len(reviews)}")
print(f"THREAD_COUNT={thread_count}")
print(f"CHECK_HITS={check_hits}")
print(f"DISCUSSION_LINES={disc_line_count}")
print(f"SA_SIGNAL={sa_signal}")
print("SA_TOOL=" + (",".join(sorted(tools)) if tools else "none"))
PY
) || skip unavailable reduce_failed

# Pull the reduced counts back into shell variables without re-reading any file.
COMMENT_COUNT=$(printf '%s\n' "$SUMMARY" | sed -n 's/^COMMENT_COUNT=//p')
REVIEW_COUNT=$(printf '%s\n' "$SUMMARY" | sed -n 's/^REVIEW_COUNT=//p')
THREAD_COUNT=$(printf '%s\n' "$SUMMARY" | sed -n 's/^THREAD_COUNT=//p')
DISCUSSION_LINES=$(printf '%s\n' "$SUMMARY" | sed -n 's/^DISCUSSION_LINES=//p')
SA_SIGNAL=$(printf '%s\n' "$SUMMARY" | sed -n 's/^SA_SIGNAL=//p')
SA_TOOL=$(printf '%s\n' "$SUMMARY" | sed -n 's/^SA_TOOL=//p')
[ -n "$SA_SIGNAL" ] && [ "$SA_SIGNAL" -gt 0 ] 2>/dev/null && SA_PRESENT=yes || SA_PRESENT=no

PR_URL=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("url") or "")' "$CTX_DIR/pr.json" 2>/dev/null)
PR_STATE=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("state") or "")' "$CTX_DIR/pr.json" 2>/dev/null)

kv PR_CONTEXT "present"
kv PR_CTX_DIR "$CTX_DIR"
kv PR_CONTEXT_NUMBER "$PR_NUM"
kv SA_PRESENT "$SA_PRESENT"
kv SA_TOOL "$SA_TOOL"
kv SA_SIGNAL "${SA_SIGNAL:-0}"

printf '%s\n' "=== FRESH-REVIEW PR CONTEXT ===" \
  "PR_CONTEXT: present" \
  "PR_NUMBER: $PR_NUM" \
  "PR_URL: $PR_URL" \
  "PR_STATE: $PR_STATE" \
  "COMMENT_COUNT: ${COMMENT_COUNT:-0}" \
  "REVIEW_COUNT: ${REVIEW_COUNT:-0}" \
  "THREAD_COUNT: ${THREAD_COUNT:-0}" \
  "DISCUSSION_LINES: ${DISCUSSION_LINES:-0}" \
  "SA_PRESENT: $SA_PRESENT" \
  "SA_TOOL: $SA_TOOL" \
  "SA_SIGNAL: ${SA_SIGNAL:-0}" \
  "=== END ==="
