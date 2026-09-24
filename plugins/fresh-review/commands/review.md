---
description: Fresh-eyes code review — runs the fresh-review skill. Pre-commit review of your branch by default; PR review when given a PR number/URL or a "what does this change do" ask; stack mode when given a stack of PRs, which plans the reviews and prints one handoff per review for you to run in a new session, then tracks the progress you report back. Desktop-executable entry point for the skill.
argument-hint: "[PR number or URL, several PRs or 'stack <PR>' for stack mode — or leave empty for a pre-commit review of your branch]"
---

Invoke the **fresh-review** skill via the Skill tool and hand it the user's request verbatim as its arguments:

$ARGUMENTS

Do not resolve the review mode, summarize, or pre-review anything yourself. The skill resolves its own mode (default pre-commit review, `pr` mode local or remote, or stack mode) from these arguments. Hand off immediately and let the skill drive the entire run.
