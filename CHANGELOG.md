# Changelog

## 0.9.0 — 2026-08-25

### `fresh-review` 0.4.1 → 0.5.0: add a slash command so the desktop app can run the review

The `fresh-review` skill could not be run from the Claude Desktop app. Selecting
`/fresh-review:fresh-review` from the desktop `/` menu returned `Unknown command: /fresh-review:fresh-review`.
Root cause: the plugin shipped only a skill (`skills/fresh-review/SKILL.md`) and no command file. The
terminal CLI auto-bridges a skill into a `/plugin:skill` slash command, so it worked there; the desktop
app's slash executor only runs real command files, so it listed the skill for discoverability but had
nothing to execute. (Sibling plugins that work in desktop — e.g. sparkpilot — ship real `commands/*.md`.)

**Fix.** Added `commands/review.md` → `/fresh-review:review`, a thin wrapper whose prompt hands the user's
arguments verbatim to the fresh-review skill via the Skill tool. A distinct command name was required: when
a command and a skill share a name, the skill takes precedence, so a same-named command would be shadowed in
the CLI and never reach the desktop's command route. The skill still resolves its own mode (default
pre-commit review vs. `pr` mode) from the passed arguments — `SKILL.md` remains the single source of truth
and is unchanged. CLI invocation (`/fresh-review:fresh-review`, bare `/fresh-review`) is unaffected; desktop
users now select `/fresh-review:review`.

### Desktop command wrappers for the remaining skill-only plugins

An audit found every other skill-only plugin had the same desktop gap: selecting `/<plugin>:<skill>` from the
desktop `/` menu returned `Unknown command`, because none shipped a command file. Added a distinctly-named
thin command wrapper per skill (each delegates to its skill via the Skill tool, passing `$ARGUMENTS`
verbatim). A distinct name is required — a same-named command is shadowed by its skill. Natural-language
triggering already worked in desktop and is unchanged; these wrappers add the slash-menu route.

- **`pull-all` 0.1.0 → 0.2.0** — `commands/run.md` → `/pull-all:run`.
- **`upgrade-all` 0.3.0 → 0.4.0** — `commands/run.md` → `/upgrade-all:run`.
- **`restaurant-search` 0.1.0 → 0.2.0** — `commands/search.md` → `/restaurant-search:search`.
- **`vault-tools` 0.3.0 → 0.4.0** — one wrapper per skill: `/vault-tools:ingest`, `:query`, `:lint`,
  `:book-digest`, `:book-note`, `:podcast` (the skills keep their `vault-` prefixed names).

The `everything` meta-plugin ships no skills of its own, so it needs no wrapper.

## 0.8.1 — 2026-08-23

### `fresh-review` 0.4.0 → 0.4.1: fix cross-marketplace dependency so the skill loads

After a Claude Code upgrade the `fresh-review` skill stopped appearing in the skill listing.
Root cause: `plugin.json` declared its lattice dependency as the string `"lattice@lattice"`.
The `plugin@marketplace` string form is not a valid `dependencies` entry — cross-marketplace
dependencies must use the object form. The resolver could not satisfy the dependency, so Claude
Code disabled the whole plugin, taking its skill with it. Every sibling ShuratCode plugin kept
loading because none declares a cross-marketplace dependency.

**Fix.** Changed the dependency to `{ "name": "lattice", "marketplace": "lattice" }`. The
`allowCrossMarketplaceDependenciesOn: ["lattice"]` allow-list in `marketplace.json` was already
correct and is unchanged. Picked up after merge by re-syncing the marketplace.

## 0.8.0 — 2026-08-23

### `vault-tools` 0.2.0 → 0.3.0: podcast ingest — `vault-podcast`

The vault's `Podcasts/` pipeline (capture note, source ladder, `transcribe.sh`, Dashboard)
existed in `AGENTS.md` and on disk, but nothing drove it. `vault-podcast` is the sixth
`vault-tools` skill and the agent side of that pipeline, deferring to `AGENTS.md` as the
single source of truth and encoding only the podcast-specific workflow.

**`vault-podcast` — turn a podcast episode into wiki.** Everything about it follows from one
fact: the agent cannot hear audio, so the durable knowledge is in the ideas discussed, never
a file it can open. It creates the capture note in `Podcasts/Inbox` (the sanctioned raw-layer
exception) and climbs the source ladder — published transcript (rung 1), Shaked's takeaways
(rung 2), show notes (rung 3), nothing (rung 4) — announcing the rung it lands on. Its spine
is the hard stop: on rung 3 or 4 it reports what's missing and asks (transcribe with `medium`
for Hebrew / give takeaways / `verdict: skip`) rather than write zettels from a marketing
blurb — the same guardrail-1 failure as the book-digest empty-notes stop. From a rung-1/2
source it runs the standard Ingest: discuss-then-write, literature note plus verdict-gated
zettels fused into existing notes, index/log, ingest stamp, archive move, one commit, reindex.

Supports the Triage and Discuss trigger modes (Discuss — "I listened to X, here's what stuck"
— is first-class, since rung 2 is often all there is and often the better filter). Hebrew
episodes produce Hebrew notes; the two legacy `Podcast`-tagged zettels are flagged for lint,
not silently retagged, and stand as fusion targets for new management / LLM-security material.

No vault content was modified — repo-only. Verified by dry-running the reasoning on two real
episodes (Radical Candor S1E15, Lang Talks / Itamar Golan); both correctly hard-stop and
write nothing.

## 0.7.0 — 2026-08-23

### `vault-tools` 0.1.0 → 0.2.0: two book skills — `vault-book-digest` and `vault-book-note`

The vault's `AGENTS.md` grew a full **Book digest flow** (2026-08-23), mirroring the new
podcast pipeline: books are a raw source whose text never enters the vault, so the only
material a digest has is what Shaked wrote in a book note's `## Notes`. Two skills implement
that contract, both deferring to `AGENTS.md`.

**`vault-book-digest` — turn a read book's notes into wiki.** Triggers only on `status: read`
+ `verdict` set + `## Notes` with substance (the `Library.base` → Ingest Queue set); never
sweeps `Books/`. Its spine is the hard stop: a `verdict` on an empty `## Notes` means there is
nothing to digest, so it stops rather than manufacture a book report from a title and a rating
— the book-shaped version of the podcast rung-3 stop, and the same guardrail-1 failure. It
corrects Shaked's fast-written names and dates and fact-checks the digest, but never pads from
general knowledge of the book (yield is bounded by his notes, not the book's length); carries
his own observations over attributed to him; writes the digest to `20 Literature/` only,
leaving `Books/` the ingest stamp; and consolidates zettels hard — the exemplar book was cut
from 56 zettels to 6.

**`vault-book-note` — create or fix a book's metadata.** Give it a title and it web-searches
the bibliographic facts (author, language, year, cover) and writes a new book note, or fills/
corrects those fields on an existing one. Metadata only: it never touches `## Notes` /
`## Review` or Shaked's curation fields (`rating`, `verdict`, `status`, dates), and never the
digest stamp. Like the digest skill it treats any non-stamp write to `Books/` as a
Shaked-authorized carve-out pending an `AGENTS.md` amendment, and confirms before writing.

Design decisions taken with Shaked: digest only at `status: read` (a book he's still reading
waits, even with rich notes); re-digests update the literature note in place; the agent's hard
stop — not a new `Library.base` surface — is the guard for the empty-notes trap the Bases
filter can't see. Both skills still await their first run on a real book, which is the true
test of whether the spec survives contact with an actual note.

## 0.6.0 — 2026-08-23

### New plugin `vault-tools` 0.1.0: ingest, query, and lint for the second-brain vault

Three skills that operate an LLM-maintained Obsidian vault following the LLM-Wiki pattern:
`vault-ingest` turns a raw source into a literature note plus fused atomic zettels,
`vault-query` answers a question from the vault's own notes with citations, and `vault-lint`
produces a health-check report of duplicates, orphans, dead links, and stale content.

**Each skill defers to the vault's `AGENTS.md` rather than restating it.** Every skill opens
by loading `AGENTS.md` in full and treats it as the single source of truth — "if this
conflicts with AGENTS.md, AGENTS.md wins." The skills encode only the workflow steps and the
triggers; the folder map, naming, tags, language rules, and guardrails live in one place, so
the vault's contract can change without a plugin release chasing it.

**They are packaged as a plugin so plugin-update keeps them current.** The skills are
vault-specific but distributed the same way as the rest of the marketplace — installed and
updated through the plugin system, not hand-copied into `~/.claude/skills`, which drifts.

`everything` 0.2.0 → 0.3.0 now depends on `vault-tools`.

## 0.5.0 — 2026-08-05

### `fresh-review` 0.3.1 → 0.4.0: a PR review mode that explains the change in plain English

fresh-review had one mode and one product: a verdict and a list of findings. It answered *is this
correct* and never *what is this*. The new `pr` mode adds the second answer — a plain-English
account of what a change does, at the altitude of someone who owns the product and does not read
code, written in the repo's own domain vocabulary rather than in file paths and function names.

**It reviews *and* narrates.** The narrative is a fourth pass added to the existing three, not a
cheaper substitute for them. A summary that has not been reviewed is how a change gets waved
through on the strength of a good description.

**The narrator is isolated exactly as hard as the critics are.** Commit messages, PR titles, plans,
and design docs are all forbidden to it. That looks perverse for a summarizer — the intent is right
there — until you notice that a narrative built from the author's description is a restatement of
the claim rather than a check on it. Built from the code alone it is the one artifact that can
*disagree* with the PR title, and Step 8 prints that disagreement as a `⚠` line. The run log records
it as `narrative.title_mismatch`, which over many runs is the direct measure of whether the mode is
telling anyone anything.

**The vocabulary is resolved and labelled, never assumed.** `fr-ddd-vocab.sh` prefers the
ddd-refiner's `.lattice/standards/ddd-principles.md`, extracting its glossary, bounded-context, and
invariant sections into a brief; with no document it falls back to generic tactical terms and says
so as `VOCAB: atom-defaults`. A narrative in the repo's real ubiquitous language and one in textbook
DDD terms read almost identically and are worth very different amounts, so the reader is told which
one they got — the same reason `HAS_GSTACK: 0` is stated rather than quietly absorbed. The
orchestrator never loads the document itself; a full refiner output runs to a thousand lines.

**Pass N is told, at length, not to write like a diff.** No paths, no line numbers, no code, no
function names except where the name is itself a domain term. No "refactored", "updated", or
"various changes". And when a change has no domain meaning — CI, lockfiles, formatting — it must say
exactly that and leave the domain sections at `none`. Inventing a domain story for a build change is
the failure that would make every future narrative untrustworthy, so it is called out as such in the
prompt, in the failure modes, and in the examples.

**`--pr 42` reviews someone else's PR**, by number or URL. `fr-pr-resolve.sh` fetches
`pull/N/head` and builds a *detached worktree* at the PR head, because reviewers are told to open
source files when the patch alone cannot settle a question — and with only a patch those reads would
hit the user's checkout, a different commit, producing confident findings about a file nobody is
proposing to merge. `SOURCE_ROOT` now points every pass, and Codex's working directory, at the right
tree. A PR in a foreign repo is refused rather than half-reviewed: there is no tree here to build.

Four things change once you are not the author, and they change the reasoning rather than the
formatting: the verdict vocabulary becomes `APPROVE` / `APPROVE-WITH-COMMENTS` / `REQUEST-CHANGES`
(`COMMIT` on someone else's PR addresses the wrong person about the wrong tree); triage bucket 2
may no longer cite "a decision from this session", because there were none; bucket 4 requires that
you actually opened the file; and the `/ship` handoff is skipped, since logging another branch's
findings into your own gate would suppress them on a branch you never reviewed.

**No mode posts anything to GitHub.** Not a comment, not a review, not a PR body — including in
pr-remote mode where a PR is plainly sitting there. Publishing under the user's name is theirs to
decide, and this skill is designed to run unattended inside `/loop`.

### Two data-loss traps found and closed while making room for it

**`fr-restore.sh` gated its index restore on `CHECKPOINT != "skipped"`.** That was exactly
equivalent to `committed|failed` for as long as those were the only other states — and pr-remote
adds a fourth. Under it nothing is ever staged, so the old test would have `read-tree`'d a
pre-review index snapshot over the live one and silently discarded anything the user staged while
the review was running. It prints `INDEX: restored`, which looks precisely like success. The gate is
now on the two states by name, and `test-pr-mode.sh` asserts that a file staged mid-review is still
staged afterwards — confirmed to fail against the old logic.

**`fr-mutation-check.sh` would have called the user's own work a reviewer leak.** Its
`committed|skipped` branch treats *any* dirt as a reviewer's, which is sound only because those two
states leave a clean tree at fan-out. pr-remote leaves the user's uncommitted work untouched and
present, so it takes the baseline-diff branch instead. It also now checks the PR worktree separately
(`PR_WT_LEAK`) — dirt there needs no revert, since restore deletes the tree, but a reviewer that
ignored "do not fix" may equally have ignored the forbidden-reads list.

**`fr-preflight.sh` gained argument parsing**, and with it the rule that an unknown flag or mode
exits non-zero instead of falling back to a default: a silently-defaulted `--pr` would review the
local branch under someone else's PR number. Its two stop conditions are also skipped under `--pr`,
both being statements about the local tree — a clean checkout on `main` is the *normal* state to
review someone else's PR from, and `nothing_to_review` there would kill the run with a message that
reads exactly like a correct answer.

### Tests

**`plugins/fresh-review/tests/test-pr-mode.sh` — 44 assertions.** `gh` is stubbed; the fetch is
real, against a local origin carrying a real `refs/pull/42/head`, the same ref name GitHub serves.
Covers ref parsing, `foreign_repo`, `gh_missing`, that `SOURCE_ROOT` holds the PR head's file
contents while the user's checkout stays on the base commit, worktree placement and teardown,
temp-ref deletion, restore idempotence, both mutation-check branches, and all three vocabulary
resolutions.

**`plugins/fresh-review/tests/test-review-mode.sh` — 20 assertions**, new coverage for the default
path, which had none. Four of the scripts it runs were edited here, so it pins the round trip a
review depends on: checkpoint → packet → mutation check → restore, ending with a staged file still
staged and an unstaged modification still unstaged.

## 0.4.2 — 2026-08-02

### Repo tooling: CI, a release gate, and the first plugin test suite

0.4.1 shipped two fixes that had been merged and silently undelivered. Nothing in the repo
could have caught either one — there was no CI at all, and `scripts/validate.sh` checks manifest
*shape*, not release *delivery*. Both gaps are now closed.

**`scripts/check-release.sh` — the release gate.** Diffs the working tree against the merge-base
with the target branch and fails when a plugin's files changed without an increase to
`plugins/<name>/.claude-plugin/plugin.json`'s `version`. Replayed against history, it blocks PR #8
and PR #9 — the two merges that shipped nothing — and passes PR #10, the bump that finally
delivered them. It also enforces the two adjacent conventions (marketplace version bump,
CHANGELOG entry) and rejects a `version` key duplicated into a marketplace entry, which can only
ever drift because Claude Code always reads plugin.json's value.

Two deliberate exemptions, both there to keep the gate credible rather than ignored:

- **Test-only changes need no bump.** `tests/` ships in the cache but cannot change installed
  behavior, and forcing a release for a test edit is the fastest way to train everyone to click
  past the failure. Matches how changesets and semantic-release treat them.
- **The gate is PR-only.** On a push to `main` the merge-base is `HEAD`, so it would compare
  nothing against nothing and pass vacuously.

**`plugins/fresh-review/tests/test-ship-gate.sh` — 26 assertions on `fr-ship-gate.sh`.** Every
assertion is on the resolved *tier*, never on "the script exited 0", because the bug it exists to
catch produced a perfectly well-formed `FR_GATE: none` — the same answer the gate legitimately
gives when there is no recent run. Confirmed to fail 13 of 26 against the pre-fix script and pass
26 of 26 after. Fixtures are built with `json.dumps`, the same serializer `fr-handoff.sh` uses, so
they track the writer instead of restating a guess about it.

**`scripts/test.sh`** runs every `plugins/*/tests/test-*.sh`. **`.github/workflows/ci.yml`** runs
validate, tests, and the release gate on every PR — with `fetch-depth: 0`, without which the
merge-base does not exist in a shallow clone and the gate cannot resolve a base.

**`scripts/validate.sh`** now also runs `claude plugin validate --strict` over the marketplace and
every plugin, skipped where the CLI is absent. It catches schema drift this repo does not model,
but note what it did *not* catch: all six manifests passed `--strict` throughout the entire period
both fixes were undelivered.

## 0.4.1 — 2026-08-02

### `fresh-review` 0.3.0 → 0.3.1

**The ship dispatch gate never matched its own review-log entry, so the whole optimization was
silently discarded.** `fr-handoff.sh` builds the handoff payload with `json.dumps`, whose default
separator emits `"skill": "fresh-review"` — with a space. `fr-ship-gate.sh` grepped the raw reader
output for the compact spelling `"skill":"fresh-review"`. It never matched, so every invocation
fell through to `no_fresh_review_entry` → `FR_GATE: none` with all four `CUT_*` flags at `no`.

The failure mode is the expensive kind: `none` is also the correct answer when there genuinely is
no recent run, so a gate that *always* returns `none` looks exactly like a gate that is working
and simply has nothing to trim. `/ship` paid for the full Step 9 specialist army on every run
that a fresh-review had already covered. The gate has been inert since it was introduced in 0.3.0.

Fixed by selecting the entry from *parsed* JSON — read each line, compare the `skill` field —
instead of text-matching one particular serialization. Writer spacing can no longer break it.
Reported by a session that reproduced the script's logic with a whitespace-tolerant match and got
the true tier (`tier1`) the gate should have returned.

Two notes for anyone editing that block:

- The selector is fed via `python3 -c "$SELECT_LAST"`, **not** `python3 - <<PY`. The heredoc form
  claims stdin, so the piped entries never arrive and the gate returns `none` again — which is
  what the first attempt at this fix did, caught only because the fixtures assert on the tier
  rather than on "the script ran".
- `entry_unparseable` is now `entry_has_no_timestamp`; a corrupt line is skipped during selection
  and falls through to `no_fresh_review_entry`. Both still resolve to `FR_GATE: none`, which
  remains the only safe default — a missed trim costs duplicated work, a wrong trim drops a lens.

Verified against fake `gstack-review-read` fixtures: spaced JSON (the real writer format) resolves
`tier1` on a drifted tree and `tier2` on a clean identical tree including `CUT_CODEX_ADVERSARIAL`,
`passes: lattice` alone leaves both Codex cuts at `no`, a dead checkpoint commit gives
`checkpoint_commit_gone`, and the five failure paths each degrade to `none` with a distinct
reason. Before the fix, all three success cases returned `none`.

**This release also finally delivers 0.4.0's `.lattice/context/**` fix, which had never reached a
single machine.** `claude plugins update` refreshes the marketplace clone but extracts into a
cache keyed on the `version` in `plugins/<name>/.claude-plugin/plugin.json`. PR #8 changed
`SKILL.md` without bumping that version, so `update` compared 0.3.0 to 0.3.0, reported `CURRENT`,
and left the stale cache in place — the forbidden-reads list running on disk still omitted
`.lattice/context/**`. Both fixes ship together here because the bump is what makes either of
them real.

The rule this implies: **a content-only change to a plugin is not shipped until its `version` is
bumped.** `CURRENT` in an upgrade summary means "the cached version string matches", not "you are
running the merged code".

## 0.4.0 — 2026-07-29

### New plugin: `pull-all` 0.1.0

`/pull-all <path>` walks a directory tree, finds every git repo under it, and brings each
one's main branch up to date with origin — in parallel, with one summary block instead of
per-repo git noise. `plugins/everything` 0.1.0 → 0.2.0 to pick it up.

The work is in `scripts/pull-all.sh`; the skill is its man page. Semantics that fell out of
testing against a fixture tree covering clean / dirty / detached / diverged / `master`-default
/ no-remote / submodule / no-local-main repos:

- **Never switches branches.** A repo checked out on `feature/x` gets its main advanced via
  `git fetch origin main:main`, which moves the ref without touching the worktree. Verified:
  the branch stays `feature/x` and the working file stays at its pre-update content while
  `main` lands exactly on `origin/main`.
- **Never merges non-fast-forward.** `merge --ff-only` for the checked-out case, a plain ref
  fetch otherwise. Ahead-*and*-behind is reported `DIVERGED` and left alone.
- **Never touches a dirty tree** (tracked modifications ⇒ `SKIPPED`; untracked files are
  ignored, since they don't block a fast-forward).
- **`git pull` is never invoked**, so a configured `pull.rebase` can't change behavior.
- Statuses sort worst-first — `FAILED`, `DIVERGED`, `SKIPPED`, then `UPDATED` / `CREATED` /
  `CURRENT` — so the lines needing a human are at the top of what the agent reads.

Two defaults exist because the first real scan of `~` got them wrong:

- **Dot-directories are pruned.** Without that, a `~` scan finds `~/.nvm` and `~/.oh-my-zsh`
  and offers to update them. `~/.nvm` sits at a detached HEAD, so it would have grown a local
  `master` branch it never had. `--hidden` opts back in.
- **A missing target branch is `SKIPPED`, not created.** Creating branches in a repo that
  deliberately has none is the surprising choice; the fetch already refreshed `origin/main`,
  so there is nothing lost. `--create` opts in.

The find expression is `\( -name '.[^.]*' ! -name .git \) -prune -o -name .git -print`. The
`! -name .git` is load-bearing — `.git` is itself a dot-name, so pruning dot-dirs without the
exclusion prunes every repo before `-print` sees it and the script silently reports zero repos.

Written for bash 3.2 (macOS `/bin/bash`): no associative arrays, no `wait -n`, no `mapfile`.
The `-j` throttle polls `jobs -rp`, and the per-repo network timeout is a hand-rolled
background-and-poll helper rather than `timeout(1)`, which macOS doesn't ship. `GIT_TERMINAL_PROMPT=0`
plus `ssh -o BatchMode=yes` mean an auth-requiring remote fails fast instead of hanging on a prompt.

#### Bare repos with linked worktrees

Running against a real 18-repo work tree found two bugs the synthetic fixtures missed, both
triggered by one repo: `core.bare = true`, files still on disk, real checkouts living in
linked worktrees (the Cursor / `.claude/worktrees` pattern).

- **A bare repo still answers `symbolic-ref HEAD` with a branch name**, so the target looked
  checked out and the run took the `merge --ff-only` path, dying with `fatal: this operation
  must be run in a work tree`. Bare is now detected with `git rev-parse --is-bare-repository`
  and routed to the ref-fetch path, which is what a bare repo wants anyway.
- **`git status` exits 128 in a bare repo, and the dirty gate read it as clean.** Only stdout
  was captured, so an errored status was indistinguishable from no modifications — the repo
  passed the safety check and then failed at the merge. A crash was the *lucky* outcome here;
  the same fail-open would have mattered more in a repo where the merge could have succeeded.
  The check now tests the exit status and reports `cannot read status`.

**Only the primary worktree is ever written to.** Nothing under `<repo>/.claude/worktrees/*`
or `~/.cursor/worktrees/*` is touched — those are in-flight task checkouts belonging to an
open session, not repos to freshen. Two layers enforce it: discovery reports a `.git` *file*
as `SKIPPED  submodule or linked worktree`, and a repo whose target branch turns out to be
checked out in a linked worktree is `SKIPPED  <branch> is checked out in linked worktree
<path>`. git also refuses to fetch into a branch checked out anywhere, so there is no safe
action in that case regardless.

Note that `git worktree list` includes the *primary* worktree, so on an ordinary repo sitting
on main the reported holder is the repo directory itself. The lookup runs only after the
`cur == target` case has returned, so normal repos never reach it and are never mistaken for
a linked holder.

Both shapes are now permanent fixtures. Verified on the work tree: 9 repos fast-forwarded to
land exactly on `origin/*`, a repo on `docs/add-agents-md` kept its branch and worktree, the
bare repo's three Cursor worktrees were untouched, and 3 dirty repos stayed dirty and
un-advanced.

## 0.3.1 — 2026-07-27

### `fresh-review` 0.2.0 → 0.2.1

**The reviewer-mutation guard was dead on clean-tree runs, and it failed silently.** Step 3 is
skipped wholesale when `DIRTY=0`, which left `CHECKPOINT` and `CHECKPOINT_SHA` unset. An unset
`CHECKPOINT` is not `committed`, so Step 6.5 took its no-checkpoint branch and diffed against a
`pre-fanout.status` that was never written. `diff` sends that error to *stderr* and `|| true`
swallows the exit code, so `LEAK` captured empty stdout and the check reported **no leak**
regardless of what a reviewer wrote to the tree. A crash would have been the better failure —
this looked like a passing safety check.

The dead path is `DIRTY=0` + `AHEAD>0`, which Step 1 itself calls "the normal shape of an open
PR whose work is fully committed and pushed" — so the guard was inert on one of the skill's most
common invocations. Reported by Copilot on `vi-activate` PR #262 (filed as low-confidence; it was
correct).

Fixed by treating the skipped case like the clean-tree case, which is the stronger of the two
available checks: when `DIRTY=0` the tree genuinely was clean at fan-out, so *any* dirt is a
leak, where a baseline snapshot would only have caught deltas. Step 3 now sets
`CHECKPOINT=skipped` explicitly, Step 6.5 matches `committed|skipped` with `case` and documents
that neither `skipped` nor an unset value may fall through, and Step 9's index restore is gated
on `!= skipped` so the code matches its own stated rule rather than relying on `read-tree`
happening to be a no-op there.

**Same root cause, second symptom: `/ship` suppression silently never applied on
fully-committed branches.** `CHECKPOINT_SHA` was also unset on the skip path, so Step 4 wrote an
empty `CHECKPOINT=` into `scope.txt` and Step 8.6 logged `"commit":""` to the handoff — matching
nothing, disabling the dedup that Step 8.6 exists to provide. Now set from `git rev-parse HEAD`.

Verified all three checkpoint states plus unset: the mutation check fires in every one, and Step
9's two undos gate correctly per state.

## 0.3.0 — 2026-07-27

### `upgrade-all` 0.2.0 → 0.3.0

**`/upgrade-all` never updated this marketplace's own plugins.** It refreshed marketplace
metadata with `claude plugins marketplace update`, then updated a hardcoded list of
`lattice`, `aws-core`, and `sparkpilot` — so `fresh-review` and its siblings stayed pinned at
whatever version was installed, indefinitely and silently. Found while checking why the local
install was still on `fresh-review` 0.1.0 after the 0.2.0 release.

The list now also covers `everything`, `fresh-review`, `restaurant-search`, and `upgrade-all`.
`upgrade-all` updates itself last: a new version installs into a sibling
`cache/<marketplace>/<plugin>/<version>/` directory rather than overwriting the running
script, so it is safe either way, but ordering it last removes the question entirely.

The `claude CLI not found` fallback branch was looping-ified so the skip list cannot drift out
of sync with the update list again — the previous form repeated each plugin name by hand and
would have needed a second edit that is easy to forget.

Verified against the real CLI that the `CURRENT` classifier still fires correctly: an
up-to-date plugin prints `✔ fresh-review is already at the latest version (0.2.0).`, which
matches the existing `already|up to date|up-to-date|no update` pattern. Without that check a
current plugin would have been mislabelled `UPGRADED` in every summary.

Skill description and body updated to name the plugins actually covered.

## 0.2.0 — 2026-07-27

### `fresh-review` 0.1.0 → 0.2.0

Driven by four problems observed across real runs in `vi-activate`, `lakehouse-kit`, and
`vi-ds-models`.

**The chat output buried the verdict.** The report file was written for the agents and the
user got a pointer to it. Added an **Output contract** and a new Step 8 with a fixed shape:
verdict on the first line, then every finding from every pass, deduplicated and tagged with
which passes raised it, bucketed into blockers / by-design / noise / misread. Disk is now
explicitly the archive, and "full report at `<path>`" is called out as not an acceptable
substitute for the findings.

**Every pass re-derived the same diff, and all their prose came home.** Added a **Token
discipline** section with four invariants, and a shared diff packet (`packet/diff.patch`,
`files.txt`, `stat.txt`, `scope.txt`) built once and handed to all four reviewers by path.
The orchestrator no longer reads the diff at all — Step 4 classifies risk with `grep -c` and
consumes only the counts. The biggest saving is the new compact return contract: each pass
writes its narrative to `raw/<pass>.md` and returns a fixed block of one-line findings.
Previously `/review`'s full output — dashboards, specialist merges, synthesis blocks — landed
in the orchestrator context verbatim.

**There were no logs.** `grep -rl fresh-review ~/.gstack/projects/` matched exactly one file,
and nothing from the three repos above; `$RAW_DIR` was a `mktemp -d`, so every raw report was
already gone. Runs now persist to `$REPORT_DIR/runs/<run_id>/` with the packet, raw reports,
`report.md`, and `run.json`, indexed in `runs.jsonl` (schema 2) and mirrored to the gstack
timeline. Per-pass durations, per-pass finding counts, triage bucket counts, and the previously
unrecorded exit code of the `/ship` handoff are all captured. The schema is deliberately
generic so a future cross-skill run-analysis tool can read it without a per-skill parser.

**Codex was the critical path.** It ran as two serial 5-minute passes *inside* Pass B's
`/review`, behind everything else that skill does. Hoisted out into Pass D, launched in the
same message as the three subagents so it overlaps them.

### Ported upstream from the vi-activate fork

The `vi-activate` copy at `.claude/skills/fresh-review/` had diverged with fixes the marketplace
version lacked. Three were live bugs here:

- **`AHEAD` was computed from `@{upstream}..HEAD`.** A fully pushed PR branch reports `AHEAD=0`, so
  with a clean tree the skill stopped with "nothing to review" while a complete reviewable diff sat
  in front of it. Now `$DIFF_BASE..HEAD`, with `@{upstream}` kept only as the fallback for when
  there is no `origin/$BASE` to merge-base against.
- **The index restore flattened partially staged files.** `STAGED_BEFORE` recorded path *names*, so
  restoring re-staged whole files and silently folded unstaged hunks into the index, destroying the
  split the user built. Replaced with `INDEX_TREE=$(git write-tree)` and `git read-tree`, which
  restores staged content exactly.
- **A failed checkpoint commit left everything staged.** `git add -A` runs before the commit, so
  treating a commit failure as "no checkpoint, skip the restore" never undid the `add`. The two
  undos are now independent: `git read-tree` runs whenever `git add -A` ran, `git reset --soft
  HEAD~1` only when the commit actually landed.

Also adopted: the unmerged-index guard (`INDEX_TREE=none` stops at preflight rather than
checkpointing a conflicted tree); **Step 6.5, a mechanical reviewer-mutation check** that
quarantines and reverts post-fan-out dirt, since subagents inherit the parent's tool access and
"do not fix anything" was unenforced prose; a **Pass A stop before lattice's "Step 5: Harvest
Learnings"**, which writes to the tracked `.lattice/learnings/operational-learnings.md` and blocks
on a confirmation question; a **Pass C stop after `/cso` Phase 12**, taking the findings report
without remediation; `SPAWNED_SESSION: true` as the non-interactive lever with an explicit warning
never to set `GSTACK_HEADLESS` (`gstack-session-kind` maps `headless` to `BLOCKED — stop and wait`);
the rationale for per-pass stop lists at all (the subagent reads the nested skill as executable
instructions and the last instruction wins); "Pass B is the expected offender" audit guidance; and
`.lattice/learnings/**` in allowed reads.

### Fixed

- **Run logs fragmented across worktrees.** `$REPORT_DIR` falls back to `$(git rev-parse --git-dir)`,
  which in a worktree resolves to `.git/worktrees/<name>` — so the index scattered per-worktree and
  was deleted with them, leaving cross-run analysis seeing a fraction of the history. Run directories
  still live at `$REPORT_DIR`, but `runs.jsonl` now goes to `$LOG_DIR`, pinned to
  `git rev-parse --git-common-dir` and shared by every worktree of a repo.
- **Pass B was the least isolated of the three passes.** `/review` Step 1.5 (Scope Drift
  Detection) plus Plan File Discovery and Fallback Intent Sources deliberately read plan files,
  `TODOS.md`, and the PR body via `gh pr view` in order to establish "stated intent" — exactly
  what the isolation contract forbids. Step 6's `FILES_READ:` audit could never have caught the
  `gh pr view` call, since it is not a file read. Pass B now names those steps and skips them,
  along with the Fix-First pipeline (which edits code, contradicting "do not fix anything"),
  Greptile, TODOS cross-reference, and docs staleness. The specialist dispatch and adversarial
  subagent — the reason the pass exists — are kept.
- **Pass B fanned out to nine nested subagents, most of them duplicates.** Unconstrained it
  dispatches seven `specialists/*.md`, plus Red Team (a separate conditional dispatch after Step
  4.6, triggered at `DIFF_LINES > 200` or any specialist CRITICAL), plus the always-on Step 5.7
  Claude adversarial subagent. `testing` and `maintainability` are marked always-on above 50
  changed lines and duplicate Pass A's lattice `test-quality` and `clean-code` atoms, directly
  contradicting Pass B's own instruction to skip clean-code findings. Pass B now dispatches
  exactly five: `security`, `performance`, `data-migration`, `api-contract`, and **Red Team** —
  kept because it is second-order, receiving the merged specialist findings and hunting what they
  missed on cross-cutting and integration boundaries, which is anti-correlated with every other
  pass by construction. `testing`, `maintainability`, and `design` are suppressed, and the Step 5.7
  Claude adversarial subagent reverts to its documented fallback role, running only when Codex is
  unavailable rather than as a third correlated adversarial lens. Red Team is force-activated on
  high-risk diffs, since suppressing three specialists lowers the odds of its CRITICAL trigger
  firing. All five are pointed at the shared packet rather than each running `git merge-base` and
  `git diff`, as their stock prompts instruct.
- Noted in the skill that `gstack-specialist-stats` reports `0 reviews analyzed`, so Step 4.5's
  `[GATE_CANDIDATE]` adaptive gating has never had data and scope gating is the only filter that
  actually operates — the specialist roster cannot be left to prune itself.
- **Convergence was treated as uniformly strong evidence.** Two Claude passes running similar
  checklists agreeing is one reviewer counted twice, not corroboration. The triage override now
  weights convergence by source independence — Codex-plus-Claude strongest, `cso`-plus-
  `gstack/security` moderate, `lattice`-plus-`gstack` on craft findings weak. Pass B tags each
  finding with the specialist that raised it so triage can tell these apart.
- **Codex used `codex exec`; switched to `codex review`.** `review` scopes natively via `--base`
  and emits structured severity-marked findings; `exec` returns prose needing a parse. Verified
  against codex-cli 0.145.0: `--base` and a custom `[PROMPT]` are mutually exclusive, so the
  isolation contract cannot be injected — acceptable, because a separate process running a
  different model family with no conversation history is already the strongest isolation here.
- **Codex no longer runs under a hard kill.** gstack sets the Bash tool's `timeout: 300000`,
  which burns the full budget and discards the work. It now runs backgrounded, making the budget
  a join deadline: late results land via a Step 8.5 addendum recording whether they moved the
  verdict, rather than being thrown away.
- Added `-c approval_policy="never" -c sandbox_mode="read-only"` so a background run cannot stall
  on an approval prompt (the user's `~/.codex/config.toml` sets `approval_mode = "approve"`), and
  so read-only is enforced by the process rather than by instruction. Dropped
  `--enable web_search_cached`, which adds latency and rarely pays on a diff review.
- Step numbering was non-monotonic in the workflow — the packet build was numbered before the
  checkpoint it must run after. Renumbered so the documented order matches the required order.
- Guarded the retention `rm -rf` on a non-empty `$REPORT_DIR` and an existing `runs/`.

Measured for context: `codex review --base` takes **29.6s on a completely empty diff** — process
start, one git probe, one model round trip. That floor is why it must never gate the verdict.

## 0.1.0 — 2026-07-27

Initial marketplace. Three authored skills, extracted from `~/.claude/skills/` and the
Claude Desktop skill store.

### Added

- `fresh-review` 0.1.0 — pre-commit review with producer/reviewer context separation.
- `upgrade-all` 0.2.0 — one-shot Homebrew / gstack / Claude-plugin maintenance.
- `restaurant-search` 0.1.0 — three-gate restaurant finder (area → open → verified menu).
- `everything` 0.1.0 — dependency-only meta-plugin installing all three.
- `chat-skills/restaurant-search` — claude.ai Chat variant.
- `scripts/validate.sh`, `scripts/build-chat-skills.sh`.

### Fixed during extraction

These were live defects in the skills as they sat in `~/.claude/skills/`:

- **`upgrade-all` would have broken on install.** It invoked
  `~/.claude/skills/upgrade-all/upgrade-all.sh`, but an installed plugin lives under
  `~/.claude/plugins/cache/…`, where that path does not exist. Now
  `${CLAUDE_PLUGIN_ROOT}/scripts/upgrade-all.sh`.
- **`upgrade-all` used a `triggers:` frontmatter key**, which Claude Code does not support
  and silently ignores — so those four trigger phrases were never matching anything. Folded
  into `description`, which is what routing actually reads.
- **`fresh-review` listed `Task` in `allowed-tools`.** No such tool exists; the entry was
  inert. Removed — `Agent` was already present and is the real one.
- **`fresh-review` hardcoded `~/.claude/skills/gstack/bin`** in its Step 7.5 handoff while
  its own preflight computed the same path into `$GSTACK_BIN`. The preflight now probes both
  known gstack locations (`~/.claude/skills/gstack`, `~/.gstack/repos/gstack`) and Step 7.5
  uses the resolved variable.

### Known limitations

- gstack cannot be a plugin dependency — it is a git clone, not a plugin. `fresh-review`
  detects it at preflight and degrades to a single-lens verdict when it is absent.
- Homebrew and the `claude` CLI likewise cannot be auto-provisioned; `upgrade-all` reports
  them `SKIPPED`.
- Claude Code has no install-time or post-install hook, so there is no sanctioned place to
  run provisioning at install. `SessionStart` is the only automatic entry point.
