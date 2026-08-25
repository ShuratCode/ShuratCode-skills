---
description: Ingest a podcast episode into the vault's wiki via the source ladder (transcript → takeaways → show notes → nothing). Runs the vault-podcast skill. Desktop-executable entry point.
argument-hint: "[an episode URL/title, 'the podcast inbox', or your takeaways]"
---

Invoke the **vault-podcast** skill via the Skill tool and hand it the user's request verbatim as its arguments:

$ARGUMENTS

Do not write zettels from show notes alone. Hand off immediately and let the vault-podcast skill climb the source ladder, deferring to the vault's AGENTS.md as its source of truth.
