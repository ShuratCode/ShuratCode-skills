---
description: Health-check the vault and produce a report of things to fix — never silent edits. Runs the vault-lint skill. Desktop-executable entry point.
argument-hint: "[optional — leave empty to lint the whole vault]"
---

Invoke the **vault-lint** skill via the Skill tool and hand it the user's request verbatim as its arguments:

$ARGUMENTS

Do not make silent edits. Hand off immediately and let the vault-lint skill run the health check, deferring to the vault's AGENTS.md as its source of truth.
