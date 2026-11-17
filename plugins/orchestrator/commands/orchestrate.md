---
description: Drive one ticket through the development pipeline — triage, spec, design, build, review, QA, harvest, ship — by starting one child session per stage and checking each child's STAGE REPORT against its completion contract. Runs the orchestrator skill. Desktop-executable entry point.
argument-hint: "[Asana task URL or ticket id, e.g. 'run triage for <url>' — or a go-word like 'start build session' in a running pipeline]"
---

Invoke the **orchestrator** skill via the Skill tool and hand it the user's request verbatim as its arguments:

$ARGUMENTS

Do not triage, start sessions, or summarize anything yourself. The skill drives the whole run.
