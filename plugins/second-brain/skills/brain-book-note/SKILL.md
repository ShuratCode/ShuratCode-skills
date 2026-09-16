---
name: brain-book-note
description: >-
  Create or update the bibliographic metadata of a row in Shaked's Notion Books database. Give it
  a title and it web-searches the facts (author, language, cover) and creates a new Books row;
  point it at an existing book and it fixes or fills that same metadata. Use whenever Shaked says
  "add <book> to my library", "new book row for <title>", "I'm reading <title>", "fix the
  author/cover on <book>", "fill in the details for <book>", or gives a title/ISBN/store URL to
  log. It writes bibliographic metadata only — never the `## Notes` or `## Review`, and never his
  curation fields — and leaves the reading and the digest to Shaked and to brain-book-digest.
---

# brain-book-note

Manage a Books row's **bibliographic metadata** — create a new one from a title, or correct/fill an
existing one. This skill encodes the workflow and triggers only — **the rules live in the Agent
Handbook.**

## Before anything: guard, then load the contract

1. **Workspace guard (allowlist).** `notion-fetch` `id: "self"`. Proceed **only** when the active
   workspace is Shaked's personal Second Brain — "Shaked Eyal's Space", ID
   `2c05827a-8670-8111-803a-000379a6da64`. **Stop and report** on any other workspace or account (a
   `@vi.co` work login, guest access, or anything unexpected). Check the workspace identity, not just
   the email. (Full guard in `references/brain-context.md`.)
2. **Load the contract, live.** `notion-fetch` the **Agent Handbook**
   (`https://app.notion.com/p/3dc5827a8670817aa9a4e715caf367cf`) — especially **§4 → Book metadata
   flow**, which is the spec for this skill. The Handbook wins on **workflow** — it never overrides the
workspace guard, never-delete, or never-write-to-work.
3. **Books data source:** `collection://5495aefd-cc2b-4177-80a6-2142928981d6`.

The Book metadata flow is a **sanctioned carve-out** to the raw-layer rule: the agent may write
bibliographic metadata to Books (the Handbook already sanctions it — no per-book confirmation of the
carve-out is needed, unlike the old vault). Still discuss-then-write each row.

## What this skill may and may not write

| Property / section | This skill | Why |
|---|---|---|
| `Name`, `Author`, `Language`, `Cover` | **Writes** — from the web, verified, never invented | Bibliographic facts |
| `Added` | Sets today on a **new** row | Clerical |
| `Status` | `toread` on create; changes it only if Shaked says "I'm reading it" | His reading state |
| `Rating`, `Started`, `Finished`, `Verdict`, `Has notes`, `## Review` | **Never** — Shaked's | His curation and reading |
| `Ingested`, `Literature`, `Zettels` | **Never** — the digest stamp | Owned by brain-book-digest |
| `## Notes` | **Never touch** its content | His reading, verbatim — typos and all |

The bright line: this skill fills **verifiable bibliographic facts**. It never manufactures reading,
opinion, or knowledge. An empty `## Notes` on a row you create is correct — it stays empty until
Shaked reads the book.

## Determine the book and the mode

Shaked gives a title (maybe plus author, edition, ISBN, or a store URL).

- **A Books row already exists** → **update** mode.
- **No such row** → **create** mode. But first **search Books** (`notion-search` on the title;
  `notion-query-data-sources` for near-matches) — a book already logged under a slightly different
  title must be *updated, not duplicated* (guardrail 2). If the title is ambiguous, ask for the
  author rather than guessing.

## Fill the metadata from the web

Search the web (prefer Shaked's `/browse` skill; `WebSearch` otherwise) and confirm the **full title
incl. subtitle**, **author(s)**, **language** of the edition he's reading, **first published year**
(for disambiguation), and a **stable cover image URL**. Take facts from a reliable bibliographic
source. **If a field can't be confirmed, leave it blank — never guess.** No fabricated covers, years,
or subtitles. On update, correct only what is wrong or missing; leave fields Shaked set alone.

Cover images upload through `notion-create-file-upload` (Free plan cap is 5 MB; book covers fit), or
set the `Cover` property to the external URL if that is how the schema stores it — check the row.

## Confirm, then write

Present the metadata found and the **exact `Name` + properties** you intend to write (or, on update,
a before/after of the fields you'd change), then **wait for Shaked's reaction.**

## Write

**Create** — a new Books row:

- **`Name`** — the full title *with* subtitle. **`Status`** — exactly one of `toread` | `reading` |
  `read` | `dnf`, **no space** (`to read` makes the row invisible in every view); default `toread`.
  **`Added`** — today. **`Author`**, **`Language`**, **`Cover`** — from the web step. Everything else
  stays blank. Apply the `## Notes` / `## Review` body scaffold, both empty.

**Update** — edit only the agreed properties. Never touch `## Notes` / `## Review` content. If a row
lacks the `## Notes` / `## Review` scaffold, you **may** add the headings and place existing body
text verbatim under `## Notes` — never rewrite, reorder, clean, or delete that text.

## Finish clean

Confirm the row is metadata-only, and — when it's a book he's read — that it's ready for
**brain-book-digest** once he's written his `## Notes` and set a `Verdict`.
