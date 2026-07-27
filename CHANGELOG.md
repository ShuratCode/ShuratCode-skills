# Changelog

## 0.1.0 — 2026-07-27

Initial marketplace. Three authored skills, extracted from `~/.claude/skills/` and the
Claude Desktop skill store.

### Added

- `fresh-review` 0.1.0 — pre-commit review with producer/reviewer context separation.
- `upgrade-all` 0.2.0 — one-shot Homebrew / gstack / Claude-plugin maintenance.
- `restaurant-search` 0.1.0 — three-gate restaurant finder (area → open → verified menu).
- `everything` 0.1.0 — dependency-only meta-plugin installing all three.
- `chat-skills/restaurant-search` — claude.ai Chat variant.
- `scripts/validate.sh`, `scripts/build-chat-skills.sh`.

### Fixed during extraction

These were live defects in the skills as they sat in `~/.claude/skills/`:

- **`upgrade-all` would have broken on install.** It invoked
  `~/.claude/skills/upgrade-all/upgrade-all.sh`, but an installed plugin lives under
  `~/.claude/plugins/cache/…`, where that path does not exist. Now
  `${CLAUDE_PLUGIN_ROOT}/scripts/upgrade-all.sh`.
- **`upgrade-all` used a `triggers:` frontmatter key**, which Claude Code does not support
  and silently ignores — so those four trigger phrases were never matching anything. Folded
  into `description`, which is what routing actually reads.
- **`fresh-review` listed `Task` in `allowed-tools`.** No such tool exists; the entry was
  inert. Removed — `Agent` was already present and is the real one.
- **`fresh-review` hardcoded `~/.claude/skills/gstack/bin`** in its Step 7.5 handoff while
  its own preflight computed the same path into `$GSTACK_BIN`. The preflight now probes both
  known gstack locations (`~/.claude/skills/gstack`, `~/.gstack/repos/gstack`) and Step 7.5
  uses the resolved variable.

### Known limitations

- gstack cannot be a plugin dependency — it is a git clone, not a plugin. `fresh-review`
  detects it at preflight and degrades to a single-lens verdict when it is absent.
- Homebrew and the `claude` CLI likewise cannot be auto-provisioned; `upgrade-all` reports
  them `SKIPPED`.
- Claude Code has no install-time or post-install hook, so there is no sanctioned place to
  run provisioning at install. `SessionStart` is the only automatic entry point.
