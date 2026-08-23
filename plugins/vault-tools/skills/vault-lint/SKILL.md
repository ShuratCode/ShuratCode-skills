---
name: vault-lint
description: >-
  Health-check this vault and produce a report of things to fix — never silent edits. Use
  whenever Shaked says "run a lint pass", "check my vault", "find duplicates/orphans", "what
  needs cleaning up", or "vault health". Scans the wiki layer for duplicates, subsumed or
  truncated notes, dead links, missing concept pages, stale employer-era content, orphans,
  and housekeeping junk, and writes a proposal report to 00 Inbox/ for Shaked to act on.
  This is the vault's Lint operation.
---

# vault-lint

Periodic health check. **The output is a report Shaked acts on — never silent edits.** This
skill encodes the workflow and triggers only — **the rules live in `AGENTS.md`**.

## Before anything: load the contract

Read **`AGENTS.md`** at the vault root in full, then skim `index.md`. `AGENTS.md` is the
single source of truth. **If anything here conflicts with `AGENTS.md`, `AGENTS.md` wins.**
The guardrails matter especially here: **never delete, never merge, never move to
`04 Archive/` without explicit approval.** Lint proposes; Shaked disposes.

## Scan the wiki layer (`10 Zettelkasten/`, `20 Literature/`, `index.md`)

Look for:

- **Duplicates / subsumed notes** — near-twins that should merge (known example:
  `מה זה למידת מכונה` exists in both `03 Resources/` and `10 Zettelkasten/`).
- **Cross-folder duplicates** — the same idea living in two layers.
- **Truncated notes** — stubs that were never finished.
- **Missing concept pages** — dead `[[links]]` and concepts referenced repeatedly with no
  note of their own.
- **Stale content** — especially Tufin-era claims superseded by Vi Labs reality.
- **Orphans** — notes with no inbound links.
- **Contradictions** between notes.
- **Housekeeping junk** — e.g. the stray Gradle project at
  `03 Resources/Images/graph-test/` flagged in `AGENTS.md`.

**Use a script for the link graph** so the orphan / dead-link pass is exhaustive rather than
sampled — parse `[[wikilinks]]` across the wiki and compute inbound-link counts. Put throwaway
scripts in the scratchpad, not the vault.

Also suggest **new questions to investigate** and **sources to look for** — gaps worth
filling.

## Output: a report, nothing else

Write to **`00 Inbox/Lint Report <YYYY-MM-DD>.md`**, tagged `type/synthesis` and `lint`.
Nothing is auto-edited. Each item is a **proposal**: what was found, where, and a recommended
action, grouped by category and ordered worst-first. Append `## [YYYY-MM-DD] lint | …` to
`log.md`, commit, and reindex qmd.

## Actioning (only after Shaked picks items)

Treat approved items as a normal edit pass under the `AGENTS.md` permissions:

- **Merges** — pick a survivor, fold the other in, **repoint every inbound link**, then
  propose (don't perform) any archival. Fuse, don't duplicate.
- **Orphans** — prefer wiring them into a **MOC hub** over scattering dozens of link edits.
- **Missing concept pages** — create the stub as a proper zettel with a `Source:` and links.
- Never delete, merge, or move to `04 Archive/` without explicit approval for that item.

Commit and reindex afterward, and log a `## [YYYY-MM-DD] lint | …` entry for the actioning
pass.

## Don't re-raise rejected items

When Shaked rejects a proposal, **record it** (a "Rejected / won't-fix" section in the report,
or a note the next pass reads) so future lint passes don't surface the same item again. A lint
that keeps re-proposing rejected work trains Shaked to ignore it.
