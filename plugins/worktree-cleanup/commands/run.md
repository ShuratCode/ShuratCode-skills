---
description: Clean up git worktrees safely — dry-run first, then delete only approved ones, never those with uncommitted changes or unpublished commits. Runs the worktree-cleanup skill. Desktop-executable entry point.
argument-hint: "[repo path — defaults to the current directory's repo]"
---

Invoke the **worktree-cleanup** skill via the Skill tool and hand it the user's request verbatim as its arguments:

$ARGUMENTS

Do not reimplement the worktree logic yourself. Hand off immediately and let the worktree-cleanup skill drive the entire run.
