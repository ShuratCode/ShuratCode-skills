---
description: Fresh-eyes code review — runs the fresh-review skill. Pre-commit review of your branch by default; PR review when given a PR number/URL or a "what does this change do" ask. Desktop-executable entry point for the skill.
argument-hint: "[PR number or URL — or leave empty for a pre-commit review of your branch]"
---

Invoke the **fresh-review** skill via the Skill tool and hand it the user's request verbatim as its arguments:

$ARGUMENTS

Do not resolve the review mode, summarize, or pre-review anything yourself. The skill resolves its own mode (default pre-commit review vs. `pr` mode, local or remote) from these arguments. Hand off immediately and let the skill drive the entire run.
