---
name: upgrade-all
description: >
  Run all routine local upgrades in one flow: Homebrew formulas and casks with cleanup,
  gstack upgrade, and Claude Code plugin updates for lattice, aws-core, sparkpilot, and the
  ShuratCode-skills plugins (everything, fresh-review, restaurant-search, upgrade-all). Use
  this whenever the user asks to "upgrade all", "full upgrade run", "upgrade brew gstack
  lattice", "maintenance upgrade", or to upgrade brew, gstack, lattice and the aws plugin
  together.
allowed-tools:
  - Bash
  - Read
---

# /upgrade-all

All upgrade work is done by a single script so this skill only reads a short summary
instead of streaming every command's output (token savings).

## 1) Run the upgrade script

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/upgrade-all.sh"
```

The script runs, in order: Homebrew (update/upgrade/cask/cleanup/autoremove), gstack
(inline non-interactive git upgrade + migrations), and the `claude plugins` updates for
lattice, aws-core, sparkpilot, and the four ShuratCode-skills plugins (`everything`,
`fresh-review`, `restaurant-search`, `upgrade-all` — self last). It prints exactly one
`=== UPGRADE-ALL SUMMARY ===` block and writes verbose per-step output to a log file.

## 2) Report the result

Read only the SUMMARY block from the script's stdout. Each line is
`component: STATUS — detail`, where STATUS is `UPGRADED`, `CURRENT`, `SKIPPED`, or
`FAILED`. Relay it to the user as a concise summary covering brew, gstack, lattice,
aws-core, sparkpilot, and the ShuratCode-skills plugins.

- Do **not** re-run the individual upgrade commands — the script already did everything.
- If any line is `FAILED`, the script appends the tail of the log and a `LOG:` path.
  Mention the failure and, only if the user wants to dig in, read that log file with the
  Read tool.

## 3) Offer to sync vendored fresh-review consumers

Run this step **only when the SUMMARY `fresh-review` line is `UPGRADED`** (its version
actually moved). If it is `CURRENT`, `SKIPPED`, or `FAILED`, skip this section entirely.

Why this exists: the Claude Desktop app cannot execute typed `/plugin:command` slash
commands, so a team consumes fresh-review as a **git-committed project skill** at
`<repo>/.claude/skills/fresh-review/`, generated from this plugin by its `vendor.sh`. When
the plugin upgrades, those vendored copies are now behind and need re-generating.

**a) Resolve the freshly-installed `vendor.sh`.** Prefer the version-keyed cache, fall back
to a marketplace checkout or a local source clone:

```bash
VENDOR=""
CACHE="$HOME/.claude/plugins/cache/ShuratCode-skills/fresh-review"
if [ -d "$CACHE" ]; then
  vd=$(ls -1d "$CACHE"/*/ 2>/dev/null | sort -V | tail -1)
  [ -n "$vd" ] && [ -f "${vd}scripts/vendor.sh" ] && VENDOR="${vd}scripts/vendor.sh"
fi
for cand in \
  "$HOME/.claude/plugins/marketplaces/ShuratCode-skills/plugins/fresh-review/scripts/vendor.sh" \
  "$HOME/ShuratCode-skills/plugins/fresh-review/scripts/vendor.sh"; do
  [ -z "$VENDOR" ] && [ -f "$cand" ] && VENDOR="$cand"
done
echo "vendor.sh: ${VENDOR:-NOT FOUND}"
```

If `VENDOR` is empty, tell the user the generator could not be located and stop this
section — do not guess a path.

**b) Pre-suggest known consumers, then ask.** A repo is a consumer iff
`<repo>/.claude/skills/fresh-review/.fresh-review-version` exists. Discover candidates
(bounded depth; widen the roots to wherever the user keeps projects):

```bash
find "$HOME" -maxdepth 7 -type f \
  -path '*/.claude/skills/fresh-review/.fresh-review-version' 2>/dev/null \
  | sed 's#/.claude/skills/fresh-review/.fresh-review-version##'
```

Present any hits as suggestions, then ask the user which repo path(s) to sync — this is a
**repeatable** choice, and the answer may include paths the scan missed. **Never hardcode a
target** (e.g. vi-activate); always ask. If the user names nothing, skip.

**c) Vendor into each chosen repo, one at a time.** For each `<repo>`:

```bash
TARGET="$repo/.claude/skills/fresh-review"
OLD_STAMP=$(cat "$TARGET/.fresh-review-version" 2>/dev/null || echo "(none)")
bash "$VENDOR" "$TARGET"
NEW_STAMP=$(cat "$TARGET/.fresh-review-version" 2>/dev/null)
echo "stamp: $OLD_STAMP -> $NEW_STAMP"
git -C "$repo" status --porcelain -- .claude/skills/fresh-review
```

Report the stamp change and the touched files. If `git status` shows nothing, the copy was
already current — say so and move on.

**d) Offer a branch + commit per repo (leave the PR to the user).** Only if that repo has
changes, ask whether to commit them. On a yes:

```bash
git -C "$repo" checkout -b "chore/sync-fresh-review-$NEW_STAMP_VERSION"
git -C "$repo" add .claude/skills/fresh-review
git -C "$repo" commit -m "chore: sync vendored fresh-review to $NEW_STAMP"
```

(Use the version portion of the stamp for the branch name.) Do **not** push or open a PR —
tell the user the branch is ready and the PR is theirs to open. If the user declines, leave
the working tree changes in place for them to review.
