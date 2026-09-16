---
description: Capture and ingest a podcast episode into Shaked's Notion second brain as a Literature row plus atomic Zettels. Runs the brain-podcast skill. Desktop-executable entry point.
argument-hint: "[an episode URL, show + guest, 'the podcast inbox', or the episode to ingest]"
---

Invoke the **brain-podcast** skill via the Skill tool and hand it the user's request verbatim as its arguments:

$ARGUMENTS

Do not reimplement the workflow yourself, and never write Zettels from show notes alone. Hand off immediately and let the brain-podcast skill drive the run, running the workspace guard and deferring to the Notion Agent Handbook as its source of truth. On show-notes-only or nothing-fetchable it stops and asks.
