---
description: Digest a book Shaked has read — turn his raw `## Notes` in a Notion Books row into a Literature row plus atomic Zettels. Runs the brain-book-digest skill. Desktop-executable entry point.
argument-hint: "[a book title, the Books row, or 'the book ingest queue']"
---

Invoke the **brain-book-digest** skill via the Skill tool and hand it the user's request verbatim as its arguments:

$ARGUMENTS

Do not reimplement the digest yourself, and never assemble one from a title, author, and rating. Hand off immediately and let the brain-book-digest skill drive the run, running the workspace guard and deferring to the Notion Agent Handbook as its source of truth. It stops cold when the notes are empty.
