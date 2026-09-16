---
name: brain-query
description: >-
  Answer a question from Shaked's Notion second brain, with citations to specific rows. Use
  whenever Shaked asks "what does my second brain say about…", "what have I read on…", "compare
  my notes on X and Y", "search my brain for…", "summarise what I know about…", or wants a
  comparison table or a synthesis page built from his own content. This is the workspace's Query
  operation — it answers from the wiki, never from general knowledge, and says so plainly when
  the workspace has no confident answer.
---

# brain-query

Answer from the workspace's own knowledge, with citations. This skill encodes the workflow and
triggers only — **the rules live in the Agent Handbook.**

## Before anything: guard, then load the contract

1. **Workspace guard (allowlist).** `notion-fetch` `id: "self"`. Proceed **only** when the active
   workspace is Shaked's personal Second Brain — "Shaked Eyal's Space", ID
   `2c05827a-8670-8111-803a-000379a6da64`. **Stop and report** on any other workspace or account (a
   `@vi.co` work login, guest access, or anything unexpected). Check the workspace identity, not just
   the email. (Full guard in `references/brain-context.md`.)
2. **Load the contract, live.** `notion-fetch` the **Agent Handbook**
   (`https://app.notion.com/p/3dc5827a8670817aa9a4e715caf367cf`) — especially **§4 → Query** and
   guardrail 1. The Handbook wins on **workflow** — it never overrides the workspace guard,
never-delete, or never-write-to-work.

The guardrail that defines this operation: **if the workspace does not support an answer, say
"the workspace has no confident answer on this."** Do not synthesise a confident-sounding answer
from low-relevance hits, and never file such an answer back — a fabrication that gets filed becomes
indistinguishable from real knowledge. On this plan it matters more: there is **no semantic
search**, so a keyword miss is not evidence of absence.

## Search

There is no qmd and no `ai_search` here. Retrieval is Notion's own:

1. **`notion-search`** with short, specific keywords. **Try more than one phrasing**, and search in
   the **source's language** — the workspace is bilingual (en/he), so run Hebrew and English queries.
2. **`notion-query-data-sources`** to filter a database precisely (Zettels by `Topics`, Literature
   by `Source type`, etc.). Use **view mode or rows mode** — SQL mode is metered on the Free plan
   and gets refused after a few calls.
3. **`notion-fetch`** to read the rows that actually matter — properties and body, not just the
   search snippet.

Search **Zettels** and **Literature** first (the wiki). Reach into the raw databases (Reading,
Podcasts, Books, Watch) only when the question is about what he read/consumed, not what he knows.

## Answer

- Read the rows that matter, not just snippets.
- Answer **with citations to specific rows** — link or @-mention each Notion page so Shaked can drill
  in.
- Ground every claim in a row. If rows disagree, **surface the contradiction** rather than papering
  over it.
- If the workspace genuinely doesn't cover it, say so plainly (guardrail 1). Offer to fill the gap
  with a web search **as a separate step**, clearly marked as outside-the-brain.

## Format on request

Offer the answer as prose, a **comparison table**, or a **new Notion synthesis page**. If he wants a
page, create it and link it; keep one idea per section, cited to the source rows.

## Let explorations compound

If the answer is worth keeping, **offer to file it back** so it doesn't die in chat (Handbook §4,
step 4):

- Atomic and durable → a new **Zettel** with `Source` (the Literature row it came from, or
  `Source URL`) and at least one `Related`. Follow the brain-ingest write path.
- Broader synthesis → a Notion page for Shaked to promote later.

Only file back a **confident, workspace-supported** answer. Filing is opt-in — offer, don't assume.
