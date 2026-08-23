---
name: vault-book-digest
description: >-
  Digest a book Shaked has read — turn his raw `## Notes` in a `Books/` note into a literature
  note plus atomic zettels in the wiki, correcting his fast-written notes and fact-checking
  them, never padding from general knowledge of the book. Use whenever Shaked says "digest
  <book>", "ingest <book title>", "I finished <book>, write it up", "process the ingest queue"
  for a book, points at a `Books/` note with `status: read` and a `verdict`, or asks what's
  waiting in `Library.base` → Ingest Queue. This is the vault's Book digest flow. It reads his
  notes, never invents a book report, and stops cold when the notes are empty.
---

# vault-book-digest

Turn a read book's raw `## Notes` into wiki. This skill encodes the workflow, the triggers,
and the book-specific judgment — **the rules live in `AGENTS.md`**.

## Before anything: load the contract

Read **`AGENTS.md`** at the vault root in full — especially **The three operations → 1. Ingest
→ Book digest flow**, which is the spec for this skill — then read `03 Resources/Templates/Book.md`
(the human-facing statement of the same contract) and skim `index.md`. Imitate the *shape* of
the one real book literature note, `20 Literature/23082026-1241 Fundamentals of Data
Engineering.md` — **not how it came to exist** (it was backfilled from a pre-rule in-book
digest; its callout and in-book twin are the exception, not the model).

**If anything here ever conflicts with `AGENTS.md`, `AGENTS.md` wins.** Internalise the
guardrails before writing: never delete; never rewrite Shaked's `## Notes`; fuse don't
duplicate; cite; write only the wiki layer plus the ingest stamp.

## Why books are different — the one fact everything follows from

The source is **not in the vault and never will be.** An article's full text is here to be
read; a book's is not. All you ever have is what Shaked wrote down while reading. That single
constraint is why the hard stop, correction-not-expansion, and notes-bounded yield below all
exist. Keep it in mind and most of the judgment calls answer themselves.

## Trigger — on demand only, never a sweep

Digest a book when **all three** hold:

1. `status: read` — **not** `reading`. A book he is still reading waits, even when its notes
   are already rich (`Books/Say Nothing…` is exactly this case: substantial notes, `status:
   reading` — do not digest it yet). One clean digest per book, when he's done.
2. `verdict` is set (`keep` | `reference` | `skip`) — his curation decision, which you read
   and never make.
3. `## Notes` has substance.

`Library.base` → `Ingest Queue` filters `status: read` + `verdict` set + not yet ingested — it
is the candidate list, and should normally be empty. **Never sweep `Books/`.** Shaked names a
book, or you work the queue he points you at.

## The hard stop — the failure this whole flow is built to prevent

If `verdict` is set but `## Notes` is **empty**, there is nothing to digest. **Stop and say
so.** Do not assemble a digest from the title, author, and rating.

The Ingest Queue can't catch this for you — `Library.base` reads frontmatter only and can't
see whether the body has substance, so an empty-notes book sits in the queue looking ready.
You are the check. This is the book-shaped version of the podcast rung-3 stop, and it fails
the same way: a plausible summary of a book you only know *about*, filed exactly where
Shaked's own reading is supposed to live, indistinguishable from real knowledge afterward.
That is guardrail 1.

## Discuss, then write — this is not optional

Present the takeaways from his notes and state **exactly** which zettels you intend to create,
which existing notes you intend to fuse into, and the corrections you found — then **wait for
his reaction.** This step is where Shaked's thinking now happens. For a book, it is also where
he catches a misread of his own shorthand before it hardens into the wiki.

## Correction, not expansion — the line that keeps the digest his

His notes are written fast: misspelled names, garbled phrases, approximate dates. Get all of
it right.

- **Correct** wrong names, dates, and mangled phrases, and **fact-check the whole digest
  before writing** — web-search (prefer Shaked's `/browse` skill; `WebSearch` otherwise)
  wherever a claim is checkable.
- **Do not add** topics, arguments, or chapters he never mentioned. Correcting what he wrote
  keeps the digest *his*; topping it up from general knowledge of the book quietly turns it
  into a book report, and the wiki cannot tell the two apart afterward.
- **Report the corrections you made**, so the boundary between his reading and your fact-check
  stays visible.

Example of the line: his note reads "Garry Adams the tactician." Fix the spelling to *Gerry
Adams* (a checkable fact about a name he clearly meant) — do **not** add the three other
figures the book covers whom he never wrote down.

## His thinking vs. the book's argument

Notes often carry Shaked's own observations, comparisons, and objections the author never made
(e.g. his comparison of the IRA's struggle to another conflict). Carry these into the
literature note **attributed to him** — his reading, not the author's position, and not yours.
Promote one to a zettel only when he asks.

## Write (order matters — mirror the Ingest steps in `AGENTS.md`)

1. **Literature note** in `20 Literature/` — the digest lives here and **only** here. Use the
   literature frontmatter and `DDMMYYYY-HHMM Title` name from `AGENTS.md`; `Source:` is the
   book, `Raw:` links the `Books/` note. Follow the book flow's sections — summary, key points,
   disagreements, how to apply, open questions — in the shape of the Fundamentals note. Nothing
   is written into `Books/` beyond the stamp, so `Books/` stays raw and guardrail 5 holds.
2. **Atomic zettels** in `10 Zettelkasten/`, gated by `verdict`: `keep` → literature note +
   zettels; `reference` → literature note only; `skip` → you should not be here. Written in
   the **same run**, never a later pass. Two book-specific cautions:
   - **Yield is bounded by his notes, not the book's length.** A 400-page book with six lines
     of notes yields one or two zettels, and that is the correct answer. A long book does not
     imply many zettels — filling the gap from general knowledge is the expansion banned above.
   - **Consolidate hard.** `Fundamentals of Data Engineering` was first extracted into 56 flat,
     barely-linked zettels and cut to 6; the survivors were the ones other notes built on.
     **qmd-search and fuse** into existing notes before creating anything new (guardrail 2).
3. **`index.md`** — add the new pages under the right topic heading.
4. **`log.md`** — append exactly `## [YYYY-MM-DD] ingest | <book title>`.
5. **Stamp the book note** — `ingested`, `zettels`, and `literature` (the link to the digest).
   **Never `verdict`** — that is Shaked's. This stamp is the only permitted write to `Books/`.
6. **`git add -A && git commit`** naming the book (one commit per book).
7. **Reindex qmd** — run `03 Resources/Scripts/qmd-reindex.sh` (or `qmd update && qmd embed`).
   Tell Shaked if you can't; the nightly launchd job is the net.

## Re-digesting — when he adds to `## Notes` later

Update the **existing** literature note in place; do not spawn a second one. Git keeps the
prior version, the `literature:` link stays stable, and fuse-don't-duplicate applies to the
digest itself. Re-run the close-out (log a fresh `ingest` line, re-stamp if zettels changed,
commit, reindex).

## Language

Hebrew `## Notes` produce a **Hebrew** literature note and **Hebrew** zettels. Never translate
his notes or the notes he'd recognise in Hebrew. When fusing into an existing Hebrew note,
write the addition in Hebrew to match.

## Finish clean

Before reporting done: verify **every new wikilink resolves** — a dead `[[link]]` is a silent
orphan — and confirm the invariant holds: the book is stamped `ingested` + `literature`, the
digest is in `20 Literature/`, and nothing was written into its `## Notes` or `## Review`.
