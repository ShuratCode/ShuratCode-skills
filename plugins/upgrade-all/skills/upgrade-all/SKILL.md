---
name: upgrade-all
description: >
  Run all routine local upgrades in one flow: Homebrew formulas and casks with cleanup,
  gstack upgrade, lattice marketplace/plugin update, aws-core plugin update, and sparkpilot
  plugin update. Use this whenever the user asks to "upgrade all", "full upgrade run",
  "upgrade brew gstack lattice", "maintenance upgrade", or to upgrade brew, gstack, lattice
  and the aws plugin together.
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
lattice, aws-core, and sparkpilot. It prints exactly one `=== UPGRADE-ALL SUMMARY ===`
block and writes verbose per-step output to a log file.

## 2) Report the result

Read only the SUMMARY block from the script's stdout. Each line is
`component: STATUS — detail`, where STATUS is `UPGRADED`, `CURRENT`, `SKIPPED`, or
`FAILED`. Relay it to the user as a concise summary covering brew, gstack, lattice,
aws-core, and sparkpilot.

- Do **not** re-run the individual upgrade commands — the script already did everything.
- If any line is `FAILED`, the script appends the tail of the log and a `LOG:` path.
  Mention the failure and, only if the user wants to dig in, read that log file with the
  Read tool.
