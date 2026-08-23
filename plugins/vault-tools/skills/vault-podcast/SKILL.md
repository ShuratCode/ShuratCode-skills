---
name: vault-podcast
description: >-
  Ingest a podcast episode into this vault's LLM-maintained wiki — create the capture note,
  climb the source ladder (transcript → Shaked's takeaways → show notes → nothing), and turn
  what's actually said into a literature note plus atomic zettels, fused into existing notes
  rather than duplicated. Use whenever Shaked says "ingest the podcast inbox", "ingest the
  <show> episode", "I listened to <episode>", "add this episode to my vault", names a podcast
  episode or pastes an episode URL, asks "what did I take from <podcast>", or asks whether an
  episode is worth listening to (triage). This is the vault's podcast Ingest operation. The one
  rule that shapes everything: the agent cannot hear audio — so it never writes zettels from
  show notes alone; on show-notes-only or nothing-fetchable it stops and asks, every time.
---

# vault-podcast

Turn a podcast episode into wiki. This skill encodes the podcast-specific workflow and
triggers only — **the rules live in `AGENTS.md`**.

## Before anything: load the contract

Read **`AGENTS.md`** at the vault root in full — especially **The three operations → 1. Ingest
→ Podcast capture flow** and the **layer-table footnote** that permits agent-created episode
notes — then read `Podcasts/README.md` (the human-facing flow) and skim `index.md` (the wiki
catalog). `AGENTS.md` is the single source of truth for folders, naming, tags, frontmatter,
language, git, permissions, and guardrails.

**If any instruction here ever conflicts with `AGENTS.md`, `AGENTS.md` wins.** Do not duplicate
its rules into your reasoning — follow them from the source. Internalise the guardrails before
writing: never delete; fuse don't duplicate; cite every claim; write only the permitted layers;
and never file back an answer the vault didn't support.

## The one fact everything follows from

**The agent cannot hear audio.** The durable knowledge is in the ideas discussed, not in a file
you can open. You never have the episode — you have, at best, a transcript or what Shaked
remembers. Every step below exists because of that single constraint. Keep it in mind and the
judgment calls answer themselves.

## Step 1 — Capture

Shaked names an episode (a URL, or just show + guest). **Create the capture note** in
`Podcasts/Inbox` from `03 Resources/Templates/Podcast Episode.md`, filename `Show - Episode
Title.md`, filling whatever metadata you can find. This is the *sanctioned exception* to "never
write to the raw layer" — see the layer-table footnote in `AGENTS.md`.

Once the note exists it is **read-only apart from the ingest stamp**. In particular, **never
rewrite the `## My notes` section** — that text is Shaked's, in his words.

If a capture note already exists for the episode, use it; do not create a twin.

## Step 2 — Climb the source ladder, and say which rung you landed on

| Rung | Source | Sufficient for zettels? |
|---|---|---|
| 1 | Published transcript (fetched, or `transcribe.sh` output in `Podcasts/Transcripts/`) | **Yes.** Full fidelity. |
| 2 | Shaked's own notes / takeaways (in `## My notes` or in chat) | **Yes.** Often the *better* filter — what he remembered is usually what mattered. |
| 3 | Show notes / episode description | **No.** Context only. |
| 4 | Nothing fetchable | **No.** |

Fetched transcripts are saved to `Podcasts/Transcripts/` as `Show - Episode Title.txt` and
linked from the note's `transcript:` field.

**Fetching is unreliable.** Many episode pages return nothing useful. Use Shaked's `/browse`
skill for the fetch (his standing preference for web work); treat a failed or empty fetch as
rung 3 or 4 and move on. Do **not** retry in a loop, and do **not** route around a blocked
fetch with shell tools (`curl`, `yt-dlp`, and the like) — a blocked page is a rung-3/4 signal,
not an obstacle to engineer past. State the rung you landed on, out loud, before going further.

## Step 3 — On rung 3 or 4, stop and ask. Every time.

This is a **hard stop, not a nudge.** Report exactly what was found and what is missing, then
let Shaked choose — do not default to any option and do not guess:

- run `03 Resources/Scripts/transcribe.sh <audio> medium` (**`medium`, not the default `base`**
  — Whisper's base model is weak on Hebrew),
- give his takeaways in chat or under `## My notes`,
- or set `verdict: skip`.

**Why this is a hard stop.** Show notes are marketing copy — a topic list and a guest bio, not
arguments. Zettels written from them are confident-sounding notes about things nobody said, and
once filed they are indistinguishable from knowledge. This is guardrail 1 (**no confident
answer**) applied to the source type that invites the failure most. Shaked chose "ask each
time" deliberately; honour it.

## Step 4 — Ingest (identical to articles from here)

Once you have a rung-1 or rung-2 source, follow the numbered **Ingest** steps in `AGENTS.md`
exactly. In summary:

1. **Read the source** — the transcript, or Shaked's notes. (Read the note's body in reverse
   order: `## My notes` and `## Transcript` carry the knowledge; `## Show notes` is context.)
2. **Discuss, then write.** Present the takeaways and state **exactly** which zettels you intend
   to create and which existing notes you intend to fuse into — then **wait for Shaked's
   reaction.** Do not skip this; it is where his thinking now happens.
3. **Literature note** in `20 Literature/` — summary, key claims (each cited), the zettels it
   produced, contradictions, open questions. Literature frontmatter and `DDMMYYYY-HHMM Title`
   name per `AGENTS.md`; `Source:` is the episode, `Raw:` links the episode note.
4. **Atomic zettels** in `10 Zettelkasten/`, one idea each. **qmd-search first** and **fuse**
   new material into an existing note rather than spawning a near-twin (see *Fusion targets*
   below). Each zettel carries a `Source:` and at least one link.
5. **`index.md`** — add the new pages under the right topic heading.
6. **`log.md`** — append exactly `## [YYYY-MM-DD] ingest | <episode title>`.
7. **Stamp the episode note** — `verdict`, `ingested`, `zettels`. The only permitted write to
   the raw note besides its birth. `verdict` is Shaked's — read it, never set it.
8. **Move** `Podcasts/Inbox → Podcasts/Archive` (the one permitted move for a podcast note).
9. **`git add` your paths && commit** with a message naming the episode (one commit per ingest).
10. **Reindex qmd** — `03 Resources/Scripts/qmd-reindex.sh` (or `qmd update && qmd embed`). Tell
    Shaked if you can't; the nightly launchd job is the net.

**Respect the verdict** — it is the curation decision, and it is Shaked's:

| Verdict | Action |
|---|---|
| `keep` | Literature note **+** atomic zettels |
| `reference` | Literature note **only**, listed in `index.md` as a reference |
| `skip` | Log it, archive it, **write nothing** |

## Trigger modes

- **Sweep** — "ingest the podcast inbox": scan `Podcasts/Inbox` for notes with `status: done`
  **and** a `verdict`. For each, climb the ladder and ingest. Skip notes without a verdict.
- **Point** — a named episode or a pasted URL: capture (if needed), climb the ladder, ingest.
- **Triage** — "is this episode worth my time?": summarise from whatever is fetchable, let
  Shaked set the verdict, *then* follow the normal path. Do not assign a verdict yourself.
- **Discuss** — "I listened to X, here's what stuck with me" with no note in existence: create
  the episode note, record his takeaways under `## My notes`, ingest from there. This is a
  **first-class path, not a fallback** — it is how most episodes will actually arrive, because
  rung 2 is often all there is and is often the better source anyway.

## Things to get right

- **Hebrew stays Hebrew.** A Hebrew episode produces a **Hebrew** literature note and **Hebrew**
  zettels. Never translate. Additions fused into an existing Hebrew note are written in Hebrew
  to match. Set `language: he` and `rtl-article` in `cssclasses` on the capture note.
- **The tag is lowercase `podcast`.** Two pre-pipeline zettels carry a capitalised `Podcast`
  tag (`27012025-2032 Radical Candor Episode 15`; `14022024-0840 … Itamar Golan`). Obsidian
  treats case as distinct. **Flag them for lint; do not silently fix them** — existing notes are
  Shaked's call.
- **Fusion targets.** The two legacy podcast zettels are live fusion targets: new management
  material may belong in the Radical Candor note, new LLM-security material in the Golan note.
  qmd-search before creating anything new.
- **Cite everything.** Every claim in a wiki page traces to a `Source:` or a wikilink.
- **Never delete.** Not files, not sections, not history.
- **Concurrency.** Another session may be working in this vault. Prefer staging your own paths
  (`git add <paths>`) over `git add -A` if the working tree has unrelated changes.

## Finish clean

Before you report done, verify **every new wikilink resolves** — a dead `[[link]]` is a silent
orphan. Confirm the invariant: nothing listened-and-ingested is left in `Podcasts/Inbox`,
nothing unrepresented sits in `Podcasts/Archive`. If you stopped at rung 3/4, there is nothing
to finish — you correctly wrote nothing, and the ball is with Shaked.
