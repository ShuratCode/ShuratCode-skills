---
description: Ingest a source (article, PDF, book) into the vault's LLM-maintained wiki as a literature note plus atomic zettels. Runs the vault-ingest skill. Desktop-executable entry point.
argument-hint: "[a URL, title, 'the reading inbox', or the source to ingest]"
---

Invoke the **vault-ingest** skill via the Skill tool and hand it the user's request verbatim as its arguments:

$ARGUMENTS

Do not reimplement the ingest workflow yourself. Hand off immediately and let the vault-ingest skill drive the run, deferring to the vault's AGENTS.md as its source of truth.
