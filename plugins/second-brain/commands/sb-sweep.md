---
description: Sweep the Notion second brain's ingest queues and post proposed takeaways for Shaked to react to — the weekly pipeline heartbeat. Runs the brain-sweep skill. Desktop-executable entry point.
argument-hint: "[optional: a specific queue, e.g. 'reading', 'podcasts', 'watch', 'books']"
---

Invoke the **brain-sweep** skill via the Skill tool and hand it the user's request verbatim as its arguments:

$ARGUMENTS

Do not write to the wiki yourself. Hand off immediately and let the brain-sweep skill drive the run, running the workspace guard and deferring to the Notion Agent Handbook as its source of truth. Sweep reads and proposes; the ingest skills write after Shaked reacts.
