---
name: vault-ingest
description: >-
  Ingest a source into this vault's LLM-maintained wiki — turn an article, PDF, or book
  into a literature note plus atomic zettels, fused into existing notes rather than
  duplicated. Use this whenever Shaked says "ingest the reading inbox", "ingest this",
  "read and ingest <url/title>", "add this to my vault", "ingest <book title>", pastes a
  URL to save, or finishes reading/curating something and wants it turned into knowledge.
  Also trigger when asked whether a source is worth their time (triage), or to process
  articles marked done-with-a-verdict. This is the vault's Ingest operation.
---

# vault-ingest

Turn a raw source into wiki. This skill encodes the workflow and triggers only — **the rules
live in `AGENTS.md`**.

## Before anything: load the contract

Read **`AGENTS.md`** at the vault root in full, then skim `index.md` (the wiki catalog).
`AGENTS.md` is the single source of truth for folders, naming, tags, frontmatter, language,
git, and guardrails. **If any instruction here ever conflicts with `AGENTS.md`, `AGENTS.md`
wins.** Do not duplicate its rules into your reasoning — follow them from the source.

Internalise the guardrails before writing: never delete; fuse don't duplicate; cite every
claim; write only the permitted layers; and never file back an answer the vault didn't
support.

## Determine the source(s)

- **Sweep** — "ingest the reading inbox": scan `Reading/Inbox` for notes with `status: done`
  **and** a `verdict`. Process each. Ignore notes without a verdict.
- **Point** — a named file or a pasted URL: ingest it immediately. Fetch the URL first if it
  isn't already saved in the vault.
- **Triage** — "is this worth my time?": summarise, let Shaked set the verdict, *then* follow
  the sweep path. Do not assign a verdict yourself and proceed.
- **Books** — on demand only, never swept. A book is ingestable **only once its `## Summary`
  is written**. An empty summary means there is nothing to extract — say so; do not
  manufacture content from a title, author, and rating.

If a pointed source has no verdict, ask for one, or infer-and-confirm before writing.

## Respect the verdict — it is the curation decision, and it is Shaked's

| Verdict | Action |
|---|---|
| `keep` | Literature note **+** atomic zettels |
| `reference` | Literature note **only**, listed in `index.md` as a reference |
| `skip` | Log it, archive it, **write nothing** |

## Discuss, then write (default mode)

Present the takeaways and state **exactly** which zettels you intend to create and which
existing notes you intend to fuse into — then **wait for Shaked's reaction**. This step is
where their thinking now happens; do not skip it.

For a large sweep, offer a lighter "write then show the diff" mode so batches don't stall on
one-by-one approval — but only if Shaked opts in.

## Write (order matters — see AGENTS.md "The three operations → Ingest")

1. **Literature note** in `20 Literature/`: summary, key claims (each cited), the zettels it
   produced, contradictions with existing notes, open questions. Use the literature
   frontmatter and the `DDMMYYYY-HHMM Title` name from `AGENTS.md`.
2. **Atomic zettels** in `10 Zettelkasten/`: one idea per note. **Search first** (qmd) and
   **fuse** new material into an existing note instead of spawning a near-twin. Consolidate
   hard across related sources. Each zettel carries a `Source:` and at least one link.
3. **`index.md`** — add the new pages under the right topic heading.
4. **`log.md`** — append exactly `## [YYYY-MM-DD] ingest | <title>`.
5. **Stamp the raw note** — `verdict`, `ingested`, `zettels`. This is the *only* permitted
   write to the raw layer.
6. If the source was in `Reading/Inbox`, **move it to `Reading/Archive`** (the one permitted
   move).
7. **`git add -A && git commit`** with a message naming the source (one commit per ingest).
8. **Reindex qmd** — `qmd update && qmd embed`, or `03 Resources/Scripts/qmd-reindex.sh`.
   Tell Shaked if you can't run it (the nightly launchd job is the safety net).

A single source may legitimately touch 10–15 files.

## Language

New agent-authored notes are in English. Hebrew notes stay Hebrew — when fusing into a Hebrew
note, write the addition in Hebrew to match. Never translate an existing Hebrew note.

## Finish clean

Before you report done, verify **every new wikilink resolves** — a dead `[[link]]` is a
silent orphan. Confirm the `Reading/Archive` invariant holds: nothing read-and-ingested is
left in `Inbox`, nothing unrepresented sits in `Archive`.
