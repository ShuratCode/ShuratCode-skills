---
description: Create or fix the bibliographic metadata of a book note in the vault's Books/ library. Runs the vault-book-note skill. Desktop-executable entry point.
argument-hint: "[a book title/ISBN/store URL, or an existing Books/ note to fix]"
---

Invoke the **vault-book-note** skill via the Skill tool and hand it the user's request verbatim as its arguments:

$ARGUMENTS

Do not write the Notes or Review sections. Hand off immediately and let the vault-book-note skill handle bibliographic metadata only, deferring to the vault's AGENTS.md as its source of truth.
