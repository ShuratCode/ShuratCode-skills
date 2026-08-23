---
name: vault-book-note
description: >-
  Create or update the metadata of a book note in this vault's `Books/` library. Give it a
  title and it web-searches the bibliographic facts (author, language, published year, cover)
  and writes a new book note from the canonical template; point it at an existing book and it
  fixes or fills that same metadata. Use whenever Shaked says "add <book> to my library", "new
  book note for <title>", "I'm reading <title>", "fix the author/cover/metadata on <book>",
  "fill in the details for <book>", or gives a title/ISBN/store URL to log. It writes
  bibliographic metadata only — never the `## Notes` or `## Review`, and never his curation
  fields — and leaves the reading and the digest to Shaked and to vault-book-digest.
---

# vault-book-note

Manage a book note's **metadata** — create a new one from a title, or correct/fill an existing
one. This skill encodes the workflow and triggers only — **the rules live in `AGENTS.md`**.

## Before anything: load the contract

Read **`AGENTS.md`** at the vault root in full, then read the canonical template
`03 Resources/Templates/Book.md` and skim `Library.base` (the library views and the
`quickAddFolder: Books` capture path). **If anything here conflicts with `AGENTS.md`,
`AGENTS.md` wins.**

## The contract boundary — read this before writing anything to `Books/`

As written, `AGENTS.md` treats `Books/` as an immutable raw layer that **Shaked** captures
(via the `Library.base` Board's QuickAdd), and lists "never write to `Books/` except the
ingest stamp." This skill writes bibliographic metadata into `Books/`, which is a **deliberate,
Shaked-authorized carve-out** — the same one paused during this skill's design.

Until `AGENTS.md` is amended to sanction it, **confirm with Shaked before writing** each book
(creating or updating), and say plainly that you are acting on his instruction ahead of the
standing contract. Do not write to `Books/` silently against the rule.

## What this skill may and may not write

| Field / section | This skill | Why |
|---|---|---|
| `title`, `author`, `language`, `cover` | **Writes** — from the web, verified, never invented | Bibliographic facts, not curation or knowledge |
| `added` | Sets today's date on a **new** note | Clerical |
| `status` | Sets `toread` on create; changes it only if Shaked says ("I'm reading it") | His reading state |
| `rating`, `started`, `finished`, `review`, `verdict` | **Never** — Shaked's | His curation and reading decisions |
| `ingested`, `literature`, `zettels` | **Never** — the digest stamp | Owned by `vault-book-digest` |
| `## Notes`, `## Review` | **Never touch** | His reading, immutable — typos and all |

The bright line: this skill fills **verifiable bibliographic facts**. It never manufactures
reading, opinion, or knowledge. An empty `## Notes` on a note you create is correct — it stays
empty until Shaked reads the book.

## Determine the book and the mode

Shaked gives a title (maybe plus author, edition, ISBN, or a store URL).

- **A `Books/` note for it already exists** → **update** mode: fix or fill its metadata.
- **No such note** → **create** mode. But first **search `Books/`** (grep the title, and qmd
  for near-matches) — a book already logged under a slightly different title must be *updated,
  not duplicated* (guardrail 2). If the title is ambiguous (a common name, multiple works),
  ask for the author rather than guessing which book he means.

## Fill the metadata from the web

Search the web (prefer Shaked's `/browse` skill; `WebSearch` otherwise) and confirm:

- **Full title incl. subtitle** — the canonical published title, subtitle kept.
- **Author(s)** — as credited.
- **Language** — `en`, `he`, etc. — the language of the edition he's reading.
- **First published year** — for disambiguation.
- **Cover image URL** — only a stable one; otherwise leave `cover` blank.

Take facts from a reliable bibliographic source. **If a field can't be confirmed, leave it
blank — never guess.** No fabricated covers, years, or subtitles. On update, correct only what
is wrong or missing; leave fields Shaked has deliberately set alone.

## Confirm, then write

Present the metadata found and the **exact filename and frontmatter** you intend to write (or,
on update, a before/after of the fields you'd change), then **wait for Shaked's reaction.**
Discuss-then-write is the vault default, and here it is also the carve-out confirmation.

## Write

**Create** — new `Books/<Title>.md` from `03 Resources/Templates/Book.md`:

- **Filename** — the full title with filename-illegal characters removed (a colon dropped, the
  subtitle kept): `AI Engineering: Building…` → `AI Engineering Building….md`. Match the
  existing `Books/` files.
- **`title`** — full title *with* subtitle, quoted. **`status`** — exactly one of `toread` |
  `reading` | `read` | `dnf`, **no space** (`to read` makes the book invisible in every
  `Library.base` view); default `toread`. **`added`** — today, `YYYY-MM-DD`. **`author`**,
  **`language`**, **`cover`** — from the web step. Everything else stays the template's blank,
  and the `## Notes` / `## Review` scaffold stays empty.

**Update** — edit only the frontmatter fields agreed above. Do not reorder or reformat the rest
of the file, and never touch `## Notes` / `## Review`.

## Finish clean

- **Reindex qmd** — `03 Resources/Scripts/qmd-reindex.sh` (or `qmd update && qmd embed`), so
  the note is searchable. Tell Shaked if you can't run it.
- **Commit** — `git add -A && git commit` naming the book (one commit per book), matching the
  vault's git discipline.
- Confirm the note is metadata-only, and — when it's a book he's read — that it's now ready for
  `vault-book-digest` once he's written his `## Notes` and set a `verdict`.
