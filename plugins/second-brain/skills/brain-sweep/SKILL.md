---
name: brain-sweep
description: >-
  Sweep Shaked's Notion second brain for work waiting in the pipeline and post proposed takeaways
  for him to react to — the weekly heartbeat that replaces the database automations the Free plan
  can't run. Use whenever Shaked says "run the weekly sweep", "what's waiting to be ingested",
  "what's in my queues", "brain sweep", or when a scheduled task fires this. It reads the
  `Awaiting ingest` views (Reading, Podcasts, Watch) and the Books `Ingest Queue`, drafts takeaways,
  and stops there — it never writes to the wiki on its own. Shaked reacts; then the ingest skills write.
---

# brain-sweep

Surface what's waiting and propose takeaways. **This skill reads and proposes — it does not write to
the wiki.** It is the "here is what I found" half of discuss-then-write; the writing happens in
brain-ingest / brain-book-digest / brain-podcast / brain-watch after Shaked reacts. This skill
encodes the workflow only — **the rules live in the Agent Handbook.**

## Why this exists

The workspace is on Notion's **Free** plan: no database automations, so nothing fires when a row
enters `Awaiting ingest`. This weekly sweep is the manual heartbeat the Handbook §9 calls for —
without it, finished-but-unprocessed rows sit invisible and the pipeline silently stalls.

## Before anything: guard, then load the contract

1. **Workspace guard (allowlist).** `notion-fetch` `id: "self"`. Proceed **only** when the active
   workspace is Shaked's personal Second Brain — "Shaked Eyal's Space", ID
   `2c05827a-8670-8111-803a-000379a6da64`. **Stop and report** on any other workspace or account (a
   `@vi.co` work login, guest access, or anything unexpected). Check the workspace identity, not just
   the email. (Full guard in `references/brain-context.md`.)
2. **Load the contract, live.** `notion-fetch` the **Agent Handbook**
   (`https://app.notion.com/p/3dc5827a8670817aa9a4e715caf367cf`) — especially §4 (the operations),
   §9 (plan facts), and the §5 guardrails. The Handbook wins on **workflow** — it never overrides
the workspace guard, never-delete, or never-write-to-work.

## Step 1 — Query the work lists

Use `notion-query-data-sources` in **view mode** (not SQL — SQL is metered on Free; the Handbook
mandates view mode for the sweep). Read each database's work-list view:

- **Reading → `Awaiting ingest`** (done + `Verdict` set + `Ingested` empty)
- **Podcasts → `Awaiting ingest`**
- **Watch → `Awaiting ingest`**
- **Books → `Ingest Queue`** (read + `Verdict` set + `Ingested` empty)

Also check the health views, and report them even when there's no ingest work:

- **Podcasts → `Blocked`** (done, transcript empty, no notes) — nothing durable behind them.
- Anything long-stuck in `Awaiting ingest` / `Ingest Queue` from a previous sweep.

## Step 2 — Read each waiting row and draft takeaways

For each row, `notion-fetch` it and read properties + body. Then, per source type, draft what you
*would* propose — respecting every hard stop, so you never propose fake takeaways:

- **Reading (articles):** summarise the piece; note the `Verdict`.
- **Podcasts:** climb the source ladder. If the row is at **rung 3/4** (show-notes-only or nothing
  fetchable), **do not draft takeaways** — flag it as "blocked, needs a transcript / your takeaways /
  skip" (brain-podcast rules).
- **Watch (videos):** same ladder; captions are often rung 1. Flag rung 3/4 the same way, and flag
  slide-heavy talks where the transcript may not carry the argument.
- **Books:** if `Has notes` is false or `## Notes` is empty, **do not draft a digest** — flag it as
  "verdict set but no notes to digest" (the brain-book-digest hard stop).
- **`skip` verdicts:** these need only the `Ingested` stamp and produce nothing — list them as
  "stamp-and-clear," no takeaways.

## Step 3 — Post the digest

Post one consolidated digest where Shaked will see it:

- **Interactive run:** present it in chat.
- **Scheduled/headless run:** create a dated Notion page (e.g. "Weekly Sweep YYYY-MM-DD" under 🧠
  Second Brain) or post it as a comment, so it isn't lost.

Structure it worst-first / most-actionable-first:

1. **Ready to ingest** — rows with a usable source and a `keep`/`reference` verdict, each with the
   proposed takeaways and the exact Zettels you'd create or fuse. This is where Shaked reacts.
2. **Blocked** — rows that hit a hard stop (podcast/video rung 3/4, empty book notes). Say exactly
   what's missing and the choices (transcribe / give takeaways / skip).
3. **Stamp-and-clear** — `skip` rows that just need the `Ingested` stamp.
4. **Pipeline health** — counts per view, anything stuck across sweeps, `Blocked` podcasts.

## Step 4 — Hand off; do not write the wiki here

**brain-sweep stops at the proposal.** When Shaked reacts to an item, hand it to the matching skill to
do the actual write:

- article → **brain-ingest** · podcast → **brain-podcast** · video → **brain-watch** · book →
  **brain-book-digest**.

The only writes brain-sweep may do directly, and only if Shaked says so in the same run, are the
`Ingested` stamps on `skip` rows (to clear them from `Awaiting ingest`). Everything else waits for his
reaction, then flows through the ingest skills. Never set a `Verdict` or `Status`.

## Scheduling

To run this weekly without being asked, wire it as a scheduled task (the `/schedule` skill, or a
cron-driven Claude Code run) that invokes this skill and posts to a Notion page. Keep the cadence
weekly — the invariant is that `Awaiting ingest` and `Ingest Queue` trend to empty between sweeps.
