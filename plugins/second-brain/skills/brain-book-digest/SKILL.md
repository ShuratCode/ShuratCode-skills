---
name: brain-book-digest
description: >-
  Digest a book Shaked has read — turn his raw `## Notes` in a Notion Books row into a Literature
  row plus atomic Zettels, correcting his fast-written notes and fact-checking them, never padding
  from general knowledge of the book. Use whenever Shaked says "digest <book>", "I finished
  <book>, write it up", "work the book ingest queue", points at a Books row with Status = read and
  a Verdict, or asks what's waiting in Books → Ingest Queue. This is the workspace's Book digest
  flow. It reads his notes, never invents a book report, and stops cold when the notes are empty.
---

# brain-book-digest

Turn a read book's raw `## Notes` into wiki. This skill encodes the workflow, the triggers, and the
book-specific judgment — **the rules live in the Agent Handbook.**

## Before anything: guard, then load the contract

1. **Workspace guard (allowlist).** `notion-fetch` `id: "self"`. Proceed **only** when the active
   workspace is Shaked's personal Second Brain — "Shaked Eyal's Space", ID
   `2c05827a-8670-8111-803a-000379a6da64`. **Stop and report** on any other workspace or account (a
   `@vi.co` work login, guest access, or anything unexpected). Check the workspace identity, not just
   the email. (Full guard in `references/brain-context.md`.)
2. **Load the contract, live.** `notion-fetch` the **Agent Handbook**
   (`https://app.notion.com/p/3dc5827a8670817aa9a4e715caf367cf`) — especially **§4 → Book digest
   flow**, which is the spec for this skill. The Handbook wins on **workflow** — it never overrides the
workspace guard, never-delete, or never-write-to-work.
3. **Data sources:** Books `collection://5495aefd-…`, Literature `collection://5e102dad-…`, Zettels
   `collection://6c988b78-…`.

Internalise before writing: never delete; never rewrite Shaked's `## Notes`; fuse don't duplicate;
cite; write only the wiki layer plus the digest stamp.

## Why books are different — the one fact everything follows from

The source is **not in the workspace and never will be.** An article's full text is a Reading row to
be read; a book's is not. All you ever have is what Shaked wrote in `## Notes` while reading. That
single constraint is why the hard stop, correction-not-expansion, and notes-bounded yield below all
exist.

## Trigger — on demand only, never a sweep

Digest a book when **all three** hold:

1. `Status` = **read** (not `reading` — a book he is still reading waits, even with rich notes).
2. `Verdict` is set (`keep` | `reference` | `skip`) — his decision, which you read and never make.
3. `Has notes` is true and `## Notes` has real substance.

The **Books → `Ingest Queue`** view (read + Verdict set + Ingested empty) is the candidate list and
should normally be empty. **Never sweep Books.** Shaked names a book, or points you at the queue.

## The hard stop — the failure this whole flow prevents

If `Verdict` is set but `## Notes` is **empty**, there is nothing to digest. **Stop and say so.** Do
not assemble a digest from the title, author, and rating. The `Ingest Queue` view reads properties
only and can't see whether the body has substance, so an empty-notes book sits there looking ready —
**you** are the check. This is the book-shaped version of the podcast rung-3 stop, and it fails the
same way: a plausible summary of a book you only know *about*, filed exactly where Shaked's own
reading lives, indistinguishable from real knowledge afterward (guardrail 1).

## Discuss, then write — not optional

Present the takeaways from his notes and state **exactly** which Zettels you intend to create, which
existing rows you intend to fuse into, and the corrections you found — then **wait for his reaction.**
For a book, this is also where he catches a misread of his own shorthand before it hardens.

## Correction, not expansion — the line that keeps the digest his

His notes are written fast: misspelled names, garbled phrases, approximate dates.

- **Correct** wrong names, dates, and mangled phrases, and **fact-check the whole digest before
  writing** — web-search (prefer `/browse`; `WebSearch` otherwise) wherever a claim is checkable.
- **Do not add** topics, arguments, or chapters he never mentioned. Correcting what he wrote keeps
  the digest *his*; topping it up from general knowledge quietly turns it into a book report the wiki
  can't distinguish afterward.
- **Report the corrections you made**, so the boundary between his reading and your fact-check stays
  visible. (Example: fix "Garry Adams" → *Gerry Adams* — a checkable fact about a name he meant — but
  do not add other figures the book covers whom he never wrote down.)

## His thinking vs. the book's argument

Notes often carry Shaked's own observations, comparisons, and objections the author never made. Carry
these into the Literature row **attributed to him** — his reading, not the author's, not yours.
Promote one to a Zettel only when he asks.

## Write (order matters — Agent Handbook §4 → Book digest flow)

1. **Literature row** — the digest lives here and **only** here. `Name`, `Topics`, `Source type` =
   `book`, `Raw (Book)` relation to the Books row, `Verdict` (copied), `Language`. Body scaffold:
   `## Summary` · `## Key claims` · `## Disagreements` · `## How to apply` · `## Open questions`;
   observations that are Shaked's are attributed to him. Nothing is written into Books beyond the
   stamp, so Books stays raw (guardrail 5).
2. **Atomic Zettels**, gated by `Verdict`: `keep` → Literature row + Zettels; `reference` →
   Literature row only; `skip` → you should not be here. Written in the **same run**, never a later
   pass. Two book-specific cautions:
   - **Yield is bounded by his notes, not the book's length.** A 400-page book with six lines of
     notes yields one or two Zettels — that is correct. Filling the gap from general knowledge is the
     expansion banned above.
   - **Consolidate hard.** *Fundamentals of Data Engineering* went from 56 flat zettels to 6; the
     survivors were the ones other notes built on. **Search Zettels and fuse** before creating
     anything new (guardrail 2).
   Set `Source` and at least one `Related` on each new Zettel; set `Zettels` on the Literature row.
3. **Stamp the Books row** — `Ingested` = today, `Literature` = the digest row. **Never `Verdict`**
   — that is Shaked's. This stamp is the only permitted write to Books here. The `Zettels` rollup
   fills itself.

## Re-digesting — when he adds to `## Notes` later

Update the **existing** Literature row in place; do not spawn a second one. `fuse-don't-duplicate`
applies to the digest itself. Re-stamp only if Zettels changed.

## Language

Hebrew `## Notes` produce a **Hebrew** Literature row and **Hebrew** Zettels. Never translate his
notes. When fusing into an existing Hebrew Zettel, write the addition in Hebrew.

## Finish clean

Confirm the book is stamped `Ingested` + `Literature`, the digest is in Literature, nothing was
written into `## Notes` or `## Review`, and each new Zettel has a `Source` and at least one `Related`.
