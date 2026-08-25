---
description: Fast-forward the main branch of every git repo under a path (git pull, ff-only). Runs the pull-all skill. Desktop-executable entry point.
argument-hint: "[path to a directory of checkouts — defaults to the skill's usual root]"
---

Invoke the **pull-all** skill via the Skill tool and hand it the user's request verbatim as its arguments:

$ARGUMENTS

Do not reimplement the pulling logic yourself. Hand off immediately and let the pull-all skill drive the entire run.
