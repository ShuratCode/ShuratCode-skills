---
name: brain-lint
description: >-
  Health-check Shaked's Notion second brain and produce a report of things to fix — never silent
  edits. Use whenever Shaked says "run a lint pass", "check my second brain", "find
  duplicates/orphans", "what needs cleaning up", or "brain health". Scans the wiki for
  duplicates, subsumed rows, dead relations, missing concept rows, stale employer-era content,
  orphans, and pipeline drift, and writes a proposal report for Shaked to act on. This is the
  workspace's Lint operation.
---

# brain-lint

Periodic health check. **The output is a report Shaked acts on — never silent edits.** This skill
encodes the workflow and triggers only — **the rules live in the Agent Handbook.**

## Before anything: guard, then load the contract

1. **Workspace guard (allowlist).** `notion-fetch` `id: "self"`. Proceed **only** when the active
   workspace is Shaked's personal Second Brain — "Shaked Eyal's Space", ID
   `2c05827a-8670-8111-803a-000379a6da64`. **Stop and report** on any other workspace or account (a
   `@vi.co` work login, guest access, or anything unexpected). Check the workspace identity, not just
   the email. (Full guard in `references/brain-context.md`.)
2. **Load the contract, live.** `notion-fetch` the **Agent Handbook**
   (`https://app.notion.com/p/3dc5827a8670817aa9a4e715caf367cf`) — especially **§4 → Lint** and the
   §5 guardrails. The Handbook wins on **workflow** — it never overrides the workspace guard,
never-delete, or never-write-to-work.

The guardrails matter especially here: **never delete, never merge, never change a raw row without
explicit approval.** Lint proposes; Shaked disposes.

## Scan

Query the databases (`notion-query-data-sources` in view/rows mode; `notion-search`; `notion-fetch`
to read rows) and look for:

- **Duplicates / near-twins** — two Zettels on the same idea that should fuse (guardrail 2).
- **Cross-layer duplicates** — the same idea living in a Zettel and a Literature row.
- **Truncated / stub rows** — started, never finished.
- **Missing concept rows** — a concept mentioned across many rows with no Zettel of its own.
- **Orphans** — the Zettels **`Orphans`** view (`Related` empty), and zettels with neither `Source`
  nor `Source URL`. This should trend towards empty.
- **Missing `Related` links** — zettels that should point at each other but don't.
- **Stale content** — especially Tufin-era claims superseded by Vi Labs reality.
- **Contradictions** between rows.
- **Pipeline drift** — rows sitting in `Awaiting ingest` (Reading, Podcasts, Watch) or `Ingest
  Queue` (Books); `Blocked` podcasts/videos; `Has notes` disagreeing with the body.

Also suggest **new questions to investigate** and **sources to look for** — gaps worth filling.

Because there is no semantic search, do the relation/orphan pass **structurally**: use the
`Orphans` view and the `Related` / `Source` / `Zettels` relations to compute inbound links, rather
than sampling by keyword.

## Output: a report, nothing else

Write the report to a **Notion page** (a dated child page under 🧠 Second Brain, e.g. "Lint Report
YYYY-MM-DD"), or present it in chat if Shaked prefers. Nothing is auto-edited. Each item is a
**proposal**: what was found, a link to the row(s), and a recommended action — grouped by category,
worst-first.

## Actioning (only after Shaked picks items)

Treat approved items as a normal edit pass under the Handbook's permissions:

- **Merges** — pick a survivor Zettel, fold the other in, **repoint every inbound `Related` /
  `Source` relation**, then propose (don't perform) anything that would need a delete. Never delete;
  Notion's trash counts as delete (guardrail 4).
- **Orphans** — prefer wiring them into a `moc` row over scattering many relation edits.
- **Missing concept rows** — create the row as a proper Zettel with a `Source` and `Related`.
- Never change a raw row's `Status` or `Verdict` (guardrail 6).

## Don't re-raise rejected items

When Shaked rejects a proposal, **record it** (a "Rejected / won't-fix" section in the report page)
so future passes don't surface the same item again. A lint that keeps re-proposing rejected work
trains him to ignore it.
