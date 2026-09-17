---
name: brain-watch
description: >-
  Capture and ingest a video (conference talk, YouTube, lecture) into Shaked's Notion second brain —
  create the Watch row, climb the source ladder (captions/transcript → Shaked's takeaways →
  description → nothing), and turn what's actually said into a Literature row plus atomic Zettels.
  Use whenever Shaked says "ingest the watch list", "ingest the <talk> video", "I watched <video>",
  "add this video", names a talk or pastes a YouTube URL, asks "what did I take from <video>", or
  asks whether a video is worth his time (triage). The rule that shapes everything: the agent cannot
  watch video or read slides — so it never writes Zettels from a description alone; on
  description-only or nothing-fetchable it stops and asks, every time.
---

# brain-watch

Turn a video into wiki. This skill encodes the video-specific workflow and triggers only — **the
rules live in the Agent Handbook.**

## Before anything: guard, then load the contract

1. **Workspace guard (allowlist).** `notion-fetch` `id: "self"`. Proceed **only** when the active
   workspace is Shaked's personal Second Brain — "Shaked Eyal's Space", ID
   `2c05827a-8670-8111-803a-000379a6da64`. **Stop and report** on any other workspace or account (a
   `@vi.co` work login, guest access, or anything unexpected). Check the workspace identity, not just
   the email. (Full guard in `references/brain-context.md`.)
2. **Load the contract, live.** `notion-fetch` the **Agent Handbook**
   (`https://app.notion.com/p/3dc5827a8670817aa9a4e715caf367cf`). The Handbook wins on **workflow** — it never overrides the workspace guard,
never-delete, or never-write-to-work.
3. **Watch data source:** `collection://2b61007b-0111-436b-b2ff-3be878182089`.

## Contract boundary — the Handbook does not yet document Watch

The 🎥 Watch database exists but the Agent Handbook (as of its 2026-09-16 version) **does not describe
it.** Watch is structurally a raw-source twin of Podcasts, so this skill applies the Podcasts rules to
it by analogy: raw layer, immutable once captured, agent writes only the stamp (`Ingested`,
`Literature`) and the row at capture; **never** set `Status` or `Verdict`.

Per guardrail 7 (**never edit the Handbook without instruction**), this skill **proposes** a Handbook
amendment adding Watch to the raw layer — it does not apply one. On first use, offer Shaked the draft
amendment (a "Watch" entry in §3's database guide and the §4 capture flow, mirroring Podcasts) and let
him add it. Until then, act on the analogy and say you are doing so.

## The one fact everything follows from

**The agent cannot watch video or read slides.** The durable knowledge is in what is said and shown;
you only ever have, at best, a transcript (which misses diagrams and on-screen text) or what Shaked
remembers. Every step below follows from that. A slide-heavy talk is a special hazard: the transcript
can read complete while the actual argument lived on the slides — when that happens, say so and lean
on rung 2.

## Step 1 — Capture

Shaked names a video (a URL, or channel + talk). **Query Watch first; if a row exists, use it, don't
create a twin.**

If not, **create the row**: `Name` (the talk title), `Captured by` = `Claude`, filling what you can
find (`Channel`, `Speaker`, `Source URL`, `Duration`, `Published`, `Language`). Unknown properties
stay blank. Apply the body scaffold `## Description` · `## Transcript` · `## My notes` (the proposed
Watch scaffold; mirrors Podcasts). `Channel` is a select — if the channel isn't an existing option,
add it with `notion-update-data-source` first, then write the row.

Once the row exists it is read-only apart from the stamp. Never rewrite `## My notes`. Never set
`Status` or `Verdict`.

## Step 2 — Climb the source ladder, and say which rung you landed on

| Rung | Source | Sufficient for Zettels? |
|---|---|---|
| 1 | Published captions/transcript (fetched, or `transcribe.sh` output) on the `Transcript` file property | **Yes**, with the slide caveat above. |
| 2 | Shaked's own takeaways (in `## My notes` or in chat) | **Yes.** Often the better filter, and it captures what the slides showed. |
| 3 | Video description / abstract | **No.** Context only. |
| 4 | Nothing fetchable | **No.** |

YouTube usually has captions — fetching them is legitimate rung-1 sourcing. Use Shaked's `/browse`
skill for the fetch. Save the transcript to the **`Transcript` file property** (upload via
`notion-create-file-upload`; Free-plan cap 5 MB — link larger files from the repo or Drive). If
captions are absent or the page blocks the fetch, that is rung 3/4 — **do not loop, do not engineer
past a block** with shell tools; move on and ask. **State the rung out loud.**

## Step 3 — On rung 3 or 4, stop and ask. Every time.

A **hard stop, not a nudge.** Report what was found and what is missing, then let Shaked choose — do
not default and do not guess:

- run `transcribe.sh <audio> medium` locally (**`medium`** for Hebrew) and attach the output,
- give his takeaways in chat or under `## My notes`,
- or set `Verdict` = `skip` (his call).

**Why a hard stop.** A video description is marketing copy — a title, an abstract, a speaker bio, not
the argument. Zettels written from it are confident notes about things nobody said, indistinguishable
from knowledge once filed (guardrail 1).

## Step 4 — Ingest (identical to podcasts/articles from here)

With a rung-1 or rung-2 source, follow the Handbook's **§4 → Ingest** steps. Read the body in reverse
order: `## My notes` and `## Transcript` carry the knowledge; `## Description` is context.

1. **Discuss, then write.** Present takeaways and state exactly which Zettels you'll create and which
   rows you'll fuse into — then **wait for Shaked's reaction.**
2. **Literature row** — `Name`, `Topics`, `Source URL`, `Source type` = `video`*, `Raw (…)` relation
   to the Watch row, `Verdict` (copied), `Language`. Body: `## Summary` · `## Key claims` ·
   `## Disagreements` · `## How to apply` · `## Open questions`.
   *`video` is a new `Source type` option and a new `Raw (Watch)` relation on Literature — both part
   of the proposed Handbook/schema amendment. If they don't exist yet, flag it and let Shaked add
   them (`notion-update-data-source`) rather than forcing a mismatched value.
3. **Atomic Zettels** — one idea each. **Search Zettels first** and **fuse** rather than spawn a
   near-twin. Each new Zettel gets `Source` and at least one `Related`; set `Zettels` on the
   Literature row.
4. **Stamp the Watch row** — `Ingested` = today, `Literature` = the new row. The only permitted write
   besides its birth. `Verdict` is Shaked's — read it, never set it.

**Respect the verdict:** `keep` → Literature row + Zettels; `reference` → Literature row only;
`skip` → stamp `Ingested`, write nothing else.

## Trigger modes

- **Sweep** — "ingest the watch list": query the Watch **`Awaiting ingest`** view. For each, climb
  the ladder and ingest.
- **Point** — a named talk or pasted URL: capture (if needed), climb the ladder, ingest.
- **Triage** — "is this video worth my time?": summarise from whatever is fetchable, let Shaked set
  the `Verdict`, *then* follow the normal path.
- **Discuss** — "I watched X, here's what stuck": create the row, record his takeaways under
  `## My notes`, ingest from there. A **first-class path** — for a slide-heavy talk it is often the
  only faithful source.

## Things to get right

- **Hebrew stays Hebrew.** A Hebrew video yields a **Hebrew** Literature row and Zettels. Set
  `Language` = `he`; pass `transcribe.sh … medium`.
- **Cite everything.** Every wiki claim traces to a `Source` relation, `Source URL`, or a mention.
- **Never delete.** Rows, blocks, history.

## Finish clean

Confirm the video has left `Awaiting ingest`, the `Raw (Watch)` relation is set on the Literature row,
and each new Zettel has a `Source` and a `Related`. If you stopped at rung 3/4, you correctly wrote
nothing — the ball is with Shaked.
