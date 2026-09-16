---
description: Ingest a source (article, PDF, podcast, video) into Shaked's Notion second brain as a Literature row plus atomic Zettels. Runs the brain-ingest skill. Desktop-executable entry point.
argument-hint: "[a URL, title, 'the reading inbox', 'the podcast inbox', or the source to ingest]"
---

Invoke the **brain-ingest** skill via the Skill tool and hand it the user's request verbatim as its arguments:

$ARGUMENTS

Do not reimplement the ingest workflow yourself. Hand off immediately and let the brain-ingest skill drive the run, running the workspace guard and deferring to the Notion Agent Handbook as its source of truth.
