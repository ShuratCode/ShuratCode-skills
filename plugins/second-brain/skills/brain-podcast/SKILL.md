---
name: brain-podcast
description: >-
  Capture and ingest a podcast episode into Shaked's Notion second brain — create the Podcasts row,
  climb the source ladder (transcript → Shaked's takeaways → show notes → nothing), and turn what's
  actually said into a Literature row plus atomic Zettels. Use whenever Shaked says "ingest the
  podcast inbox", "ingest the <show> episode", "I listened to <episode>", "add this episode",
  names an episode or pastes an episode URL, asks "what did I take from <podcast>", or asks whether
  an episode is worth his time (triage). The one rule that shapes everything: the agent cannot hear
  audio — so it never writes Zettels from show notes alone; on show-notes-only or nothing-fetchable
  it stops and asks, every time.
---

# brain-podcast

Turn a podcast episode into wiki. This skill encodes the podcast-specific workflow and triggers only
— **the rules live in the Agent Handbook.**

## Before anything: guard, then load the contract

1. **Workspace guard (allowlist).** `notion-fetch` `id: "self"`. Proceed **only** when the active
   workspace is Shaked's personal Second Brain — "Shaked Eyal's Space", ID
   `2c05827a-8670-8111-803a-000379a6da64`. **Stop and report** on any other workspace or account (a
   `@vi.co` work login, guest access, or anything unexpected). Check the workspace identity, not just
   the email. (Full guard in `references/brain-context.md`.)
2. **Load the contract, live.** `notion-fetch` the **Agent Handbook**
   (`https://app.notion.com/p/3dc5827a8670817aa9a4e715caf367cf`) — especially **§4 → Ingest →
   Podcast capture flow**. The Handbook wins on **workflow** — it never overrides the workspace
guard, never-delete, or never-write-to-work.
3. **Podcasts data source:** `collection://77d248a2-6695-433e-8f63-d57ed9aa9980`.

## The one fact everything follows from

**The agent cannot hear audio.** The durable knowledge is in the ideas discussed, not in a file you
can open. You never have the episode — you have, at best, a transcript or what Shaked remembers.
Every step below exists because of that single constraint.

## Step 1 — Capture

Shaked names an episode (a URL, or just show + guest). Instinct may already have created the row —
**query Podcasts first; if a row exists, use it, don't create a twin.**

If not, **create the row** in Podcasts: `Name` = `Show - Episode Title`, `Captured by` = `Claude`,
filling whatever metadata you can find (`Show`, `Episode`, `Source URL`, `Host`, `Guest`,
`Published`, `Language`). Unknown properties stay blank. This is the *sanctioned exception* to "never
write to the raw layer" (Handbook §4, guardrail 5). Apply the body scaffold: `## Show notes` ·
`## Transcript` · `## My notes`.

Once the row exists it is **read-only apart from the ingest stamp**. Never rewrite `## My notes` —
that text is Shaked's. Never set `Status` or `Verdict` — his (guardrail 6).

## Step 2 — Climb the source ladder, and say which rung you landed on

| Rung | Source | Sufficient for Zettels? |
|---|---|---|
| 1 | Published transcript (fetched, or `transcribe.sh` output) attached to the `Transcript` file property | **Yes.** Full fidelity. |
| 2 | Shaked's own takeaways (in `## My notes` or in chat) | **Yes.** Often the *better* filter — what he remembered is what mattered. |
| 3 | Show notes / episode description | **No.** Context only. |
| 4 | Nothing fetchable | **No.** |

Fetched transcripts go on the **`Transcript` file property** (upload via `notion-create-file-upload`;
Free-plan cap is 5 MB — link anything larger from the repo or Drive), not pasted into the body.

**Fetching is unreliable.** Use Shaked's `/browse` skill for the fetch (his standing preference for
web work); treat a failed or empty fetch as rung 3/4 and move on. Do **not** retry in a loop, and do
**not** route around a blocked fetch with shell tools (`curl`, `yt-dlp`) — a blocked page is a
rung-3/4 signal, not an obstacle to engineer past. **State the rung out loud** before going further.

## Step 3 — On rung 3 or 4, stop and ask. Every time.

A **hard stop, not a nudge.** Report exactly what was found and what is missing, then let Shaked
choose — do not default and do not guess:

- run `transcribe.sh <audio> medium` locally (**`medium`, not the default `base`** — Whisper's base
  model is weak on Hebrew) and attach the output to `Transcript`,
- give his takeaways in chat or under `## My notes` (then set `Has notes`),
- or set `Verdict` = `skip` (his call).

**Why a hard stop.** Show notes are marketing copy — a topic list and a guest bio, not arguments.
Zettels written from them are confident-sounding notes about things nobody said, and once filed they
are indistinguishable from knowledge. This is guardrail 1 applied to the source type that invites the
failure most.

## Step 4 — Ingest (identical to articles from here)

With a rung-1 or rung-2 source, follow the Handbook's **§4 → Ingest** steps. Read the body in reverse
order: `## My notes` and `## Transcript` carry the knowledge; `## Show notes` is context.

1. **Discuss, then write.** Present takeaways and state exactly which Zettels you'll create and which
   rows you'll fuse into — then **wait for Shaked's reaction.**
2. **Literature row** — `Name`, `Topics`, `Source URL`, `Source type` = `podcast`, `Raw (Podcast)`
   relation to the episode, `Verdict` (copied), `Language`. Body: `## Summary` · `## Key claims` ·
   `## Disagreements` · `## How to apply` · `## Open questions`.
3. **Atomic Zettels** — one idea each. **Search Zettels first** and **fuse** into an existing row
   rather than spawning a near-twin. Each new Zettel gets `Source` and at least one `Related`; set
   `Zettels` on the Literature row.
4. **Stamp the episode row** — `Ingested` = today, `Literature` = the new row. The only permitted
   write besides its birth. `Verdict` is Shaked's — read it, never set it.

**Respect the verdict:** `keep` → Literature row + Zettels; `reference` → Literature row only;
`skip` → stamp `Ingested`, write nothing else.

## Trigger modes

- **Sweep** — "ingest the podcast inbox": query the Podcasts **`Awaiting ingest`** view. For each,
  climb the ladder and ingest.
- **Point** — a named episode or pasted URL: capture (if needed), climb the ladder, ingest.
- **Triage** — "is this episode worth my time?": summarise from whatever is fetchable, let Shaked set
  the `Verdict`, *then* follow the normal path.
- **Discuss** — "I listened to X, here's what stuck with me" with no row yet: create the row, record
  his takeaways under `## My notes`, set `Has notes`, ingest from there. A **first-class path** — rung
  2 is often all there is, and often the better source.

## Things to get right

- **Hebrew stays Hebrew.** A Hebrew episode produces a **Hebrew** Literature row and **Hebrew**
  Zettels. Never translate. Set `Language` = `he`. Pass `transcribe.sh … medium` for Hebrew audio.
- **Cite everything.** Every wiki claim traces to a `Source` relation, `Source URL`, or a mention.
- **Never delete.** Rows, blocks, history. Notion's trash counts as delete.

## Finish clean

Confirm the episode has left `Awaiting ingest`, exactly one `Raw (Podcast)` relation is set on the
Literature row, and each new Zettel has a `Source` and a `Related`. If you stopped at rung 3/4, there
is nothing to finish — you correctly wrote nothing, and the ball is with Shaked.
