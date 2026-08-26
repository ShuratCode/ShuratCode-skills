---
name: vault-route
description: >-
  Sweep this vault's `00 Inbox/` and route each captured note to its correct home — the vault's
  Route operation. Web-clipped articles are normalised into `Reading/Inbox` reading notes so they
  enter the reading pipeline; a few high-confidence known types (meetings, recipes) go to their
  PARA folder; anything ambiguous stays put and is reported. Use whenever Shaked says "route the
  inbox", "route my inbox", "clear the inbox", "sweep 00 Inbox", "sort my inbox", "process my
  captures", "file my mobile clips", "what's piled up in my inbox", or after clipping articles on
  his phone that landed in `00 Inbox/`. This is routing, not ingest — it relocates and normalises,
  it never writes zettels, never sets a verdict, and never deletes.
---

# vault-route

Sweep `00 Inbox/` and move each capture to its correct home. This skill encodes the workflow and
triggers only — **the rules live in `AGENTS.md`**.

## Before anything: load the contract

Read **`AGENTS.md`** at the vault root in full, paying attention to **The four operations → 4.
Route**, the folder map, and the guardrails. `AGENTS.md` is the single source of truth for folders,
naming, tags, frontmatter, language, and guardrails. **If any instruction here ever conflicts with
`AGENTS.md`, `AGENTS.md` wins.** Do not duplicate its rules into your reasoning — follow them from
the source.

Internalise before touching anything: never delete; never overwrite Shaked's content; never set
`verdict` (his alone); preserve plugin syntax (Dataview, Templater, `- [ ]` tasks); and route
**working-area captures only** — `Reading/Archive`, `Books/`, `Podcasts/`, and
`rss-dashboard-data/` are out of scope.

## Why this operation exists

Shaked captures on his phone with the Obsidian Web Clipper, which can **only** write into
`00 Inbox/`. So mobile web clips — mostly articles — pile up there mixed in with the odd hand-typed
note. The RSS Dashboard and the desktop Web Clipper already save straight into `Reading/Inbox` with
correct frontmatter; Route is only for what lands in `00 Inbox/`. Your job is to get each note to
the folder it should have been in, and to turn raw article clips into proper reading notes so they
join the reading → ingest pipeline.

## Step 1 — classify every note in `00 Inbox/`

Read each `.md` file in `00 Inbox/` (skip folder notes and anything that is clearly an index/queue).
Assign one type. The signals below are guides, not a checklist — use judgement, and when a note
doesn't clearly fit a routable type, that *is* the answer: it stays put.

| Type | What it looks like | Destination |
|---|---|---|
| **Article clip** | Web-clipped prose. Usually **no frontmatter**, or frontmatter with no `type/` tag. Body opens on article text, a byline (`by …`), a URL, a TL;DR, or headings like Intro / Why. This is the dominant case. | `Reading/Inbox/` (normalised — see Step 2) |
| **Meeting note** | Meeting structure (`## Meeting Purpose`, `## Action Items`, `Participants:` with `[[people]]`), or an ISO-dated `YYYY-MM-DD - Person - Topic` shape. | `02 Areas/Work/Meetings/` |
| **Recipe** | Ingredients + steps, cooking verbs, often a Hebrew food title. | `02 Areas/Personal/Food/Recipes/` |
| **Idea / zettel-candidate** | A short atomic thought Shaked typed himself. | **Stays** — flag as a promote-candidate. Zettels are agent-authored during *ingest*, not routed. |
| **Working / handoff doc** | Planning notes, handoffs, drafts. Often `type/synthesis`. No single PARA home. | **Stays** — flag. |
| **Agent report** | Lint reports, sweep reports the agent itself produced. | **Stays** — flag. |
| **Unknown** | Doesn't clearly fit any of the above. | **Stays** — flag. |

**High confidence is the bar for moving.** Only articles, meetings, and recipes are routed in this
version, and only when the signals are unambiguous. Everything else — including ideas and anything
you are unsure about — stays in `00 Inbox/` and goes in the report. Forcing a low-confidence move is
the one failure that matters here: a misfiled note is worse than one left in the inbox, because the
inbox is *expected* to hold unsorted things and the wrong folder hides the note where Shaked won't
look. When torn between two homes, leave it and say why in the report.

## Step 2 — normalise article clips into reading notes

A mobile clip is raw: no frontmatter, no title header, just the article. Turn it into the same shape
every other `Reading/Inbox` note has (frontmatter → `# Title` → info callout → `---` → body),
matching `Reading/Templates/Article.md`.

Build the frontmatter:

```yaml
---
type: article
status: unread
source:            # the original URL, if the clip carries one — else leave blank
author:            # byline, if present — else blank
published:         # original publish date, if present — else blank
saved: <today>     # YYYY-MM-DD, the day you route it
feed:              # site / domain, if derivable (e.g. "Netflix TechBlog") — else blank
language: en       # or he — detect from the body
progress:
finished:
priority:
verdict:
ingested:
zettels:
cssclasses:
  - article-reader
tags:
  - reading
---
```

Then a `# Title` (from the filename, or the article's own top heading), an info callout populated
only with the fields you actually have, a `---`, and **the clipped body verbatim below it**:

```markdown
# <title>

> [!info]
> **Source:** [Original article](<url>)
> **Author:** <author>
> **Published:** <published>
> **Feed:** <feed>

---

<the article body, exactly as clipped>
```

**Rules that keep the note honest:**

- **Extract, don't invent.** Pull `source` / `author` / `published` / `feed` from the clip when they
  are actually there — a URL in the body, a `by …` byline, a dateline, the domain. When a field
  isn't in the clip, **leave it blank and drop its callout line.** Guessing a publish date or an
  author is worse than an empty field: the empty field is honestly unknown, the guess is wrong and
  looks authoritative. This is the vault's no-confident-fabrication guardrail applied to metadata.
- **Body verbatim.** Normalising means wrapping the clip in the standard header — it does **not**
  mean touching the article prose. Don't summarise, reword, or trim it. Preserve any plugin syntax
  intact.
- **Hebrew clips.** If the body is Hebrew, set `language: he` and add `rtl-article` under
  `cssclasses` so it renders right-to-left.
- **Do not set a verdict, and do not ingest.** Routing an article just files it into the reading
  queue. Shaked reads it and sets the verdict later; ingest is a separate operation.
- **Filename.** Keep the existing filename — it's already the human title and may be linked. Only
  adjust if it carries an illegal character.

## Step 3 — propose the routing table, then move (default mode)

Do **not** move anything first. Classify everything, then present a routing table and wait for
Shaked to confirm the batch. This mirrors the vault's discuss-then-write / lint-report ethos: moves
change paths and are the kind of thing that should never happen behind his back.

Present it like this — destination, and for anything staying, the reason:

```
## Inbox route — <N> notes

**Articles → Reading/Inbox/** (normalised)
- <filename>  · source/author/published extracted: <what you found, or "none in clip">

**Known types → PARA**
- <filename>  → 02 Areas/Work/Meetings/   (meeting: <signal>)

**Staying in 00 Inbox/** (flagged)
- <filename>  — <type>: <why it's staying>
```

Then ask Shaked to confirm, adjust, or drop items. Only after he confirms do you make the moves.
(If he ever says "just move the articles, ask me about the rest", follow that — but the default is
confirm-the-batch.)

## Step 4 — execute the confirmed moves

For each confirmed note:

- **Articles:** write the normalised content, then move the file to `Reading/Inbox/`. Use `git mv`
  where the file is unchanged apart from location; where you rewrote the frontmatter, write the new
  content at the destination and remove the inbox copy in the same step so history stays clean.
  Never leave both copies — that would duplicate the note in search.
- **Known types:** `git mv` to the destination folder. Don't rewrite the body; a meeting or recipe
  Shaked typed is his content.
- **Staying:** leave untouched.

Verify after moving: the file exists at exactly one path, and no dead `[[wikilink]]` elsewhere
pointed at its old location (grep the vault for the old basename if unsure).

## Step 5 — close out

1. **One commit** describing the sweep, e.g. `route: sweep 00 Inbox — 2 articles to Reading/Inbox,
   2 flagged`. One commit for the whole sweep, not one per file.
2. **Reindex qmd** so search reflects the new paths — `03 Resources/Scripts/qmd-reindex.sh` (or
   `qmd update && qmd embed`). Moves change paths, so the index is stale until you do. Tell Shaked
   if you can't run it; the nightly launchd job is the safety net.

## Finish clean

Report what moved and what stayed, and why each flagged note stayed — that list is how Shaked
decides what to do with the leftovers (promote an idea, give a handoff a project home, delete a
stale report himself). Confirm nothing was deleted and no verdict was set. Route leaves the inbox
holding only what genuinely has no confident home yet.
