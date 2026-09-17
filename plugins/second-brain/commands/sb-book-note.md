---
description: Create or fix the bibliographic metadata of a row in Shaked's Notion Books database (author, language, cover). Runs the brain-book-note skill. Desktop-executable entry point.
argument-hint: "[a book title, ISBN, store URL, or the Books row to fix]"
---

Invoke the **brain-book-note** skill via the Skill tool and hand it the user's request verbatim as its arguments:

$ARGUMENTS

Do not write the digest or touch his reading. Hand off immediately and let the brain-book-note skill drive the run, running the workspace guard and deferring to the Notion Agent Handbook as its source of truth. Bibliographic metadata only — never `## Notes`, `## Review`, or curation fields.
