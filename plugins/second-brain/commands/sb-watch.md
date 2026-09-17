---
description: Capture and ingest a video (conference talk, YouTube, lecture) into Shaked's Notion second brain as a Literature row plus atomic Zettels. Runs the brain-watch skill. Desktop-executable entry point.
argument-hint: "[a video URL, channel + talk, 'the watch list', or the video to ingest]"
---

Invoke the **brain-watch** skill via the Skill tool and hand it the user's request verbatim as its arguments:

$ARGUMENTS

Do not reimplement the workflow yourself, and never write Zettels from a description alone. Hand off immediately and let the brain-watch skill drive the run, running the workspace guard and deferring to the Notion Agent Handbook as its source of truth. Watch is not yet in the Handbook — the skill proposes an amendment rather than editing it. On description-only or nothing-fetchable it stops and asks.
