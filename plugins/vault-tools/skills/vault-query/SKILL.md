---
name: vault-query
description: >-
  Answer a question from this vault's own notes, with citations to specific notes. Use this
  whenever Shaked asks "what does my vault say about…", "what have I read on…", "compare my
  notes on X and Y", "search my vault for…", "summarise what I know about…", or wants a
  comparison table or a Marp deck built from vault content. This is the vault's Query
  operation — it answers from the wiki, never from general knowledge, and says so when the
  vault has no confident answer.
---

# vault-query

Answer from the vault's own knowledge, with citations. This skill encodes the workflow and
triggers only — **the rules live in `AGENTS.md`**.

## Before anything: load the contract

Read **`AGENTS.md`** at the vault root in full, then skim `index.md` (the wiki catalog).
`AGENTS.md` is the single source of truth. **If anything here conflicts with `AGENTS.md`,
`AGENTS.md` wins.**

The guardrail that defines this operation: **if the vault does not support an answer, say
"the vault has no confident answer on this."** Do not synthesise a confident-sounding answer
from low-relevance hits, and never file such an answer back — a fabrication that gets filed
becomes indistinguishable from real knowledge.

## Search

1. **qmd MCP tools first** (`query`, `get`, `multi_get`, `status`) — the local hybrid
   search over the whole vault. Search **both Hebrew and English**; the index embeds both.
   Use `lex` for exact terms, `vec`/`hyde` for meaning; combine them. Filter weak hits
   (`minScore ~0.5`).
2. Fall back to **`index.md`** (the catalog), then **grep** for exact strings and for
   `04 Archive/`, which qmd deliberately does not index.

## Answer

- Read the notes that actually matter, not just snippets.
- Answer **with citations to specific notes** — wikilinks or paths, so Shaked can drill in.
- Ground every claim in a note. If the notes disagree, surface the contradiction rather than
  papering over it.
- If the vault genuinely doesn't cover it, say so plainly (see the guardrail above). Offer to
  fill the gap with a web search *as a separate step*, clearly marked as outside-the-vault.

## Format on request

Offer the answer as prose, a **comparison table**, or a **Marp deck**:

- Decks go in `03 Resources/Decks/`. Front-matter `marp: true`, `---` between slides, speaker
  notes citing the source zettels. Keep one idea per slide, in the vault's register.

## Let explorations compound

If the answer is worth keeping, **offer to file it back** so it doesn't die in chat:

- Atomic and durable → a new zettel in `10 Zettelkasten/` (follow the Ingest write path in
  `vault-ingest` / `AGENTS.md`: cite, link, index, log, commit, reindex).
- Broader synthesis → into `00 Inbox/` tagged `type/synthesis`, for Shaked to promote.

Only file back a **confident, vault-supported** answer. Filing is opt-in — offer, don't
assume. Commit and reindex if you do.
